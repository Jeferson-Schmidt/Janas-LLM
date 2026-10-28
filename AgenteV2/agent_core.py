"""
Núcleo do agente: sessão, laço de ferramentas e compactação de contexto.

Regra que guia tudo aqui: a conversa enviada ao janas-server SÓ CRESCE NO FIM.
Os modelos usados (Qwen3.6 e Qwen3-Next) têm estado recorrente; se qualquer
mensagem antiga mudar, o servidor relê a conversa inteira do zero. Por isso:
  - a data no prompt de sistema é fixada quando a sessão nasce;
  - a lista de ferramentas é sempre a mesma (para "não usar ferramenta" usamos
    tool_choice="none" em vez de tirar as ferramentas, que mudaria o início);
  - a compactação pede o resumo acrescentando uma mensagem no fim (o servidor
    lê só ela) e depois recomeça a conversa, pequena, a partir do resumo.

Memórias separadas por sessão:
  - messages: memória de conversa, o que vai para o modelo;
  - research: memória de pesquisa, com o resultado completo de cada pesquisa
    (fontes, tempos, tokens); para a conversa vai só o resumo curto.
"""

from __future__ import annotations

import asyncio
import json
import secrets
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Awaitable, Callable

import config
import research
from janas_client import add_usage, main_client, merge_counter, model_stats, new_counter, parse_usage, reasoning_body

Emit = Callable[[dict], Awaitable[None]]

SYSTEM_PROMPT = (
    "Você é Janas, um assistente rodando localmente no computador do usuário. "
    "Hoje é {data}. Você tem a ferramenta web_research, que pesquisa na internet, "
    "lê {paginas} páginas e devolve um resumo com as fontes. Use-a quando a pergunta "
    "depender de informação atual, de algo que pode ter mudado ou de um fato do qual "
    "você não tem certeza; para conversa comum, conhecimento estável ou cálculos, "
    "responda direto, sem pesquisar. Prefira uma pesquisa bem formulada a várias "
    "pequenas. Quando o usuário passar um link (URL) e pedir algo sobre ele, use "
    "fetch_url com esse endereço exato em vez de web_research: a busca não abre "
    "links específicos. Se fetch_url falhar, informe o erro que ela devolveu. "
    "Não invente URLs nem dados: use só o que a pesquisa trouxe e cite os "
    "sites. Se a pesquisa não trouxer nada útil, diga isso. Responda no idioma do "
    "usuário, de forma direta."
)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "web_research",
            "description": (
                "Pesquisa na internet, lê as principais páginas (inclusive as que "
                "dependem de JavaScript) e devolve um resumo com as fontes."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Consulta de busca específica, com nomes, versões ou datas relevantes.",
                    }
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "fetch_url",
            "description": (
                "Abre um endereço específico (página, arquivo do GitHub, texto, JSON) "
                "e devolve o conteúdo dele. Use quando o usuário fornecer um link."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "O endereço completo, exatamente como o usuário passou, começando com http:// ou https://.",
                    }
                },
                "required": ["url"],
            },
        },
    },
]

COMPACT_PROMPT = (
    "[Instrução interna do agente, não é o usuário] O contexto está quase cheio. "
    "Resuma esta conversa para continuá-la depois: objetivo do usuário, fatos e "
    "conclusões importantes (inclusive resultados de pesquisas, com as URLs), "
    "preferências e pendências. Seja conciso, em tópicos. Não use ferramentas."
)


@dataclass
class Session:
    id: str
    think: bool = config.THINK_DEFAULT
    system: str = ""
    messages: list[dict] = field(default_factory=list)
    research: list[research.ResearchResult] = field(default_factory=list)
    transcript: list[dict] = field(default_factory=list)
    context_used: int = 0
    totals: dict = field(default_factory=lambda: {"conversa": new_counter(), "resumos": new_counter()})
    compactions: int = 0
    busy: bool = False
    cancel: asyncio.Event = field(default_factory=asyncio.Event)
    last_used: float = field(default_factory=time.time)

    def __post_init__(self) -> None:
        if not self.system:
            self.reset()

    def reset(self) -> None:
        self.system = SYSTEM_PROMPT.format(
            data=datetime.now().strftime("%d/%m/%Y"), paginas=config.PAGES_PER_SEARCH
        )
        self.messages = [{"role": "system", "content": self.system}]
        self.research = []
        self.transcript = []
        self.context_used = 0
        self.compactions = 0

    def state(self) -> dict:
        limite = main_client.effective_context
        return {
            "think": self.think,
            "busy": self.busy,
            "transcript": self.transcript,
            "research": [r.as_dict() for r in reversed(self.research)],
            "context": {
                "used": self.context_used,
                "limit": limite,
                "configured": config.CONTEXT_WINDOW,
                "server": main_client.context_size,
                "compact_at": config.COMPACT_AT,
            },
            "totals": self.totals,
            "model_stats": model_stats.dados,
            "rate_min": {"read": config.RATE_MIN_READ_TOKENS, "gen": config.RATE_MIN_GEN_TOKENS},
            "compactions": self.compactions,
            "model": main_client.display_model,
        }


# --------------------------------------------------------------------------
# Chamadas ao modelo principal
# --------------------------------------------------------------------------

async def _stream(s: Session, emit: Emit, permitir_ferramentas: bool):
    """Uma chamada em streaming. Devolve (texto, tool_calls, uso, interrompido)."""
    cliente = main_client
    if cliente.lock.locked():
        await emit({"type": "status", "text": "Na fila do janas-server (outra conversa está usando o modelo)..."})
    texto, tool_calls_acc, uso_bruto, interrompido = [], {}, None, False
    async with cliente.lock:
        await emit({"type": "status", "text": "Modelo lendo o contexto e gerando..."})
        stream = await cliente.api.chat.completions.create(
            model=cliente.model,
            messages=s.messages,
            tools=TOOLS,
            tool_choice="auto" if permitir_ferramentas else "none",
            temperature=config.TEMPERATURE,
            max_tokens=config.ANSWER_MAX_TOKENS,
            stream=True,
            stream_options={"include_usage": True},
            extra_body=reasoning_body(s.think),
        )
        try:
            async for chunk in stream:
                if s.cancel.is_set():
                    interrompido = True
                    break
                if getattr(chunk, "usage", None):
                    uso_bruto = chunk.usage
                if not chunk.choices:
                    continue
                delta = chunk.choices[0].delta
                if delta is None:
                    continue
                raciocinio = getattr(delta, "reasoning_content", None) or (delta.model_extra or {}).get("reasoning_content")
                if raciocinio:
                    await emit({"type": "reasoning", "text": raciocinio})
                if delta.content:
                    texto.append(delta.content)
                    await emit({"type": "delta", "text": delta.content})
                for tc in delta.tool_calls or []:
                    item = tool_calls_acc.setdefault(
                        tc.index, {"id": None, "type": "function", "function": {"name": "", "arguments": ""}}
                    )
                    if tc.id:
                        item["id"] = tc.id
                    if tc.function and tc.function.name:
                        item["function"]["name"] += tc.function.name
                    if tc.function and tc.function.arguments:
                        item["function"]["arguments"] += tc.function.arguments
        finally:
            await stream.close()

    uso = parse_usage(uso_bruto)
    if uso_bruto is not None:
        cliente.learn(uso)
        s.context_used = uso.context_used
        model_stats.record(cliente.display_model, "conversa", uso.as_dict())
    tool_calls = [tool_calls_acc[i] for i in sorted(tool_calls_acc)]
    for n, tc in enumerate(tool_calls):
        tc["id"] = tc["id"] or f"call_{n}"
    return "".join(texto), tool_calls, uso, interrompido


async def compact(s: Session, emit: Emit) -> None:
    """Resume a conversa e recomeça a partir do resumo para liberar contexto."""
    cliente = main_client
    await emit({"type": "status", "text": "Contexto quase cheio: compactando a conversa..."})
    try:
        async with cliente.lock:
            resposta = await cliente.api.chat.completions.create(
                model=cliente.model,
                messages=s.messages + [{"role": "user", "content": COMPACT_PROMPT}],
                tools=TOOLS,
                tool_choice="none",
                temperature=0.2,
                max_tokens=config.COMPACT_MAX_TOKENS,
                extra_body=reasoning_body(False),
            )
        resumo = (resposta.choices[0].message.content or "").strip()
        uso = parse_usage(resposta.usage).as_dict()
        add_usage(s.totals["conversa"], uso)
        model_stats.record(cliente.display_model, "conversa", uso)
    except Exception as exc:
        resumo = ""
        await emit({"type": "status", "text": f"Falha ao resumir ({exc}); descartando as mensagens mais antigas."})

    if resumo:
        s.messages = [{
            "role": "system",
            "content": f"{s.system}\n\nResumo da conversa anterior (compactada para liberar contexto):\n{resumo}",
        }]
    else:
        # Plano B: mantém a segunda metade, começando numa mensagem do usuário.
        resto = s.messages[1:]
        corte = len(resto) // 2
        while corte < len(resto) and resto[corte]["role"] != "user":
            corte += 1
        s.messages = [s.messages[0]] + resto[corte:]
    s.compactions += 1
    s.context_used = sum(len(str(m.get("content") or "")) for m in s.messages) // 3  # estimativa até a próxima resposta
    await emit({"type": "compacted", "summary": resumo, "compactions": s.compactions})


# --------------------------------------------------------------------------
# Um turno: pergunta do usuário -> (pesquisas) -> resposta
# --------------------------------------------------------------------------

async def run_turn(s: Session, pergunta: str, emit: Emit) -> None:
    s.busy = True
    s.cancel.clear()
    s.last_used = time.time()
    inicio = time.perf_counter()
    try:
        try:
            if not main_client.model:
                await main_client.discover_model()
        except Exception as exc:
            await emit({"type": "error", "text": f"janas-server offline em {main_client.base_url} ({exc}). "
                                                 "Inicie-o no outro terminal com run-chat-web.ps1."})
            return

        # Só compacta se houver conversa para compactar: logo depois de uma
        # compactação sobram só o sistema e um turno, e repetir não liberaria nada.
        if s.context_used >= config.COMPACT_AT * main_client.effective_context and len(s.messages) > 3:
            await compact(s, emit)

        tamanho_antes = len(s.messages)
        s.messages.append({"role": "user", "content": pergunta})
        s.transcript.append({"role": "user", "content": pergunta})
        turno = {"conversa": new_counter(), "resumos": new_counter()}
        pesquisas: list[research.ResearchResult] = []
        resposta = ""

        try:
            for rodada in range(config.MAX_TOOL_ROUNDS + 1):
                # Na última rodada o modelo é obrigado a responder com o que já tem.
                conteudo, tool_calls, uso, interrompido = await _stream(
                    s, emit, permitir_ferramentas=rodada < config.MAX_TOOL_ROUNDS
                )
                add_usage(turno["conversa"], uso.as_dict())
                if interrompido or not tool_calls:
                    resposta = conteudo + ("\n\n_(interrompido)_" if interrompido else "")
                    # Mesmo interrompida, a resposta parcial entra no histórico:
                    # assim a conversa continua só crescendo no fim.
                    s.messages.append({"role": "assistant", "content": conteudo or "(interrompido)"})
                    break

                s.messages.append({"role": "assistant", "content": conteudo or None, "tool_calls": tool_calls})
                for chamada in tool_calls:
                    try:
                        args = json.loads(chamada["function"]["arguments"] or "{}")
                    except json.JSONDecodeError:
                        args = {}
                    nome = chamada["function"]["name"]
                    if nome not in ("web_research", "fetch_url"):
                        conteudo_tool = f"Ferramenta desconhecida: {nome}"
                    else:
                        if nome == "fetch_url":
                            consulta = (args.get("url") or "").strip()
                            await emit({"type": "tool", "query": consulta, "kind": "url"})
                            r = await research.fetch_url(consulta, pergunta, emit)
                        else:
                            consulta = (args.get("query") or pergunta).strip()
                            await emit({"type": "tool", "query": consulta, "kind": "busca"})
                            r = await research.research(consulta, pergunta, emit)
                        s.research.append(r)
                        pesquisas.append(r)
                        # Pesquisa vinda do cache não chamou o modelo agora:
                        # somar o uso antigo inflaria tokens e tempos.
                        if r.usage and not r.from_cache:
                            add_usage(turno["resumos"], r.usage)
                        await emit({"type": "research", **r.as_dict()})
                        conteudo_tool = r.to_tool_message()
                    s.messages.append({"role": "tool", "tool_call_id": chamada["id"], "content": conteudo_tool})

                if s.cancel.is_set():
                    resposta = "_(interrompido depois da pesquisa)_"
                    s.messages.append({"role": "assistant", "content": "(interrompido)"})
                    break
        except Exception as exc:
            # Falha de comunicação: desfaz o turno inteiro.
            del s.messages[tamanho_antes:]
            s.transcript.pop()
            await emit({"type": "error", "text": f"Erro ao falar com o janas-server: {exc}"})
            return

        for nome in ("conversa", "resumos"):
            merge_counter(s.totals[nome], turno[nome])

        fontes = [{**f, "query": r.query} for r in pesquisas for f in r.sources]
        uso_turno = {**turno, "seconds": round(time.perf_counter() - inicio, 2)}
        s.transcript.append({"role": "assistant", "content": resposta, "sources": fontes, "usage": uso_turno})
        s.busy = False
        await emit({"type": "done", "usage": uso_turno, "state": s.state()})
    finally:
        s.busy = False
        s.last_used = time.time()


# --------------------------------------------------------------------------
# Uma conversa por navegador
# --------------------------------------------------------------------------

class SessionStore:
    def __init__(self) -> None:
        self._sessions: dict[str, Session] = {}

    def get(self, sid: str | None) -> Session:
        agora = time.time()
        for chave, sess in list(self._sessions.items()):
            if not sess.busy and agora - sess.last_used > config.SESSION_IDLE_SECONDS:
                del self._sessions[chave]
        if sid and sid in self._sessions:
            sess = self._sessions[sid]
            sess.last_used = agora
            return sess
        while len(self._sessions) >= config.MAX_SESSIONS:
            livres = [x for x in self._sessions.values() if not x.busy]
            if not livres:
                break
            del self._sessions[min(livres, key=lambda x: x.last_used).id]
        sess = Session(id=sid or secrets.token_urlsafe(16))
        self._sessions[sess.id] = sess
        return sess


sessions = SessionStore()
