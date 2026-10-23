"""
Agente de chat local para o Janas LLM com acesso a busca na internet.

Como funciona:
  1. Conecta no janas-server via API compatível com OpenAI (http://127.0.0.1:8080/v1).
     O janas-server precisa já estar rodando (ex: .\\scripts\\run-chat-web.ps1 ou
     um janas-server iniciado manualmente) com um modelo carregado.
  2. Declara uma ferramenta "web_search" para o modelo.
  3. Quando o modelo pede pra usar a ferramenta, este script executa a busca de
     verdade em Python e devolve o resultado pro modelo continuar a resposta.
     A internet nunca é acessada pelo Janas-server em si, apenas por este
     processo Python, que roda isolado em seu próprio venv.
  4. As respostas chegam em streaming (texto aparece sendo escrito, em vez de
     esperar a geração inteira terminar) e cada turno mostra quantos tokens
     foram gastos, com um total acumulado da sessão.

Pré-requisitos (dentro do venv isolado, ver scripts\\setup-agent.ps1):
  pip install openai ddgs

Variáveis de ambiente opcionais:
  JANAS_BASE_URL   (padrão: http://127.0.0.1:8080/v1)
  JANAS_API_KEY    (padrão: "not-needed" -- só importa se o janas-server foi
                    iniciado com --api-key)
  JANAS_MODEL      (padrão: qwen3.6-35b-a3b -- deve bater com o modelo que o
                    janas-server já tem carregado nesta sessão)
  JANAS_THINK      ("off" por padrão -- desliga o raciocínio/reasoning do
                    modelo por requisição, sem precisar reiniciar o servidor.
                    Use "on" para reativar.)
"""

from __future__ import annotations

import json
import os
import sys

from openai import OpenAI

try:
    from ddgs import DDGS
except ImportError:  # pacote mais antigo, caso ainda esteja instalado assim
    from duckduckgo_search import DDGS  # type: ignore


# --------------------------------------------------------------------------
# Configuração
# --------------------------------------------------------------------------

JANAS_BASE_URL = os.environ.get("JANAS_BASE_URL", "http://127.0.0.1:8080/v1")
JANAS_API_KEY = os.environ.get("JANAS_API_KEY", "not-needed")
JANAS_MODEL = os.environ.get("JANAS_MODEL", "qwen3.6-35b-a3b")
JANAS_THINK = os.environ.get("JANAS_THINK", "off").strip().lower()  # "off" ou "on"

MAX_TOOL_ROUNDS = 4  # trava de segurança contra loop infinito de chamadas de ferramenta

# Quantos resultados de busca pedir, e quantos caracteres de cada um devolver
# pro modelo. Resultados menores = menos tokens pra reler = resposta final
# mais rápida, especialmente em CPU.
SEARCH_MAX_RESULTS = 3
SEARCH_SNIPPET_CHARS = 220

SYSTEM_PROMPT = (
    "Você é um assistente rodando localmente no computador do usuário, sem "
    "acesso à internet por padrão. Quando a pergunta depender de informação "
    "atual, de algo que pode ter mudado, ou de um fato que você não tem "
    "certeza, use a ferramenta web_search antes de responder. Não invente "
    "URLs nem resultados -- só cite o que a ferramenta realmente retornou. "
    "Se a ferramenta não achar nada útil, diga isso claramente."
)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": (
                "Busca na internet usando o DuckDuckGo. Use para informações "
                "atuais, preços, notícias, versões de software ou qualquer "
                "fato que possa ter mudado depois do treinamento do modelo."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Termos de busca, em poucas palavras.",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": f"Quantos resultados retornar (padrão {SEARCH_MAX_RESULTS}).",
                        "default": SEARCH_MAX_RESULTS,
                    },
                },
                "required": ["query"],
            },
        },
    }
]


# --------------------------------------------------------------------------
# Ferramenta real: busca na internet
# --------------------------------------------------------------------------

def web_search(query: str, max_results: int = SEARCH_MAX_RESULTS) -> str:
    """Executa a busca de verdade e devolve um texto resumido para o modelo."""
    try:
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
    except Exception as exc:  # qualquer falha de rede/rate-limit cai aqui
        return f"A busca falhou ({exc}). Informe isso ao usuário em vez de inventar uma resposta."

    if not results:
        return "Nenhum resultado encontrado para essa busca."

    linhas = []
    for r in results:
        titulo = r.get("title", "(sem título)")
        corpo = (r.get("body", "") or "")[:SEARCH_SNIPPET_CHARS]
        url = r.get("href", "")
        linhas.append(f"- {titulo}: {corpo} ({url})")
    return "\n".join(linhas)


def executar_ferramenta(nome: str, argumentos: dict) -> str:
    if nome == "web_search":
        return web_search(
            query=argumentos.get("query", ""),
            max_results=argumentos.get("max_results", SEARCH_MAX_RESULTS),
        )
    return f"Ferramenta desconhecida solicitada pelo modelo: {nome}"


# --------------------------------------------------------------------------
# Contador de tokens (acumulado na sessão)
# --------------------------------------------------------------------------

class ContadorTokens:
    def __init__(self) -> None:
        self.prompt_total = 0
        self.completion_total = 0

    def registrar(self, usage) -> tuple[int, int]:
        """Soma o uso de uma chamada e devolve (prompt, completion) dessa chamada."""
        if usage is None:
            return (0, 0)
        prompt = getattr(usage, "prompt_tokens", None) or 0
        completion = getattr(usage, "completion_tokens", None) or 0
        self.prompt_total += prompt
        self.completion_total += completion
        return (prompt, completion)

    @property
    def total(self) -> int:
        return self.prompt_total + self.completion_total

    def resumo_sessao(self) -> str:
        return (
            f"tokens na sessão: {self.total} "
            f"(prompt {self.prompt_total} + resposta {self.completion_total})"
        )


def extra_body_reasoning() -> dict:
    """Liga/desliga o raciocínio do modelo por requisição (sem reiniciar o servidor)."""
    pensar = JANAS_THINK != "off"
    return {
        "reasoning_effort": "medium" if pensar else "none",
        "chat_template_kwargs": {"enable_thinking": pensar},
    }


# --------------------------------------------------------------------------
# Uma chamada ao modelo, em streaming, com fallback para não-streaming
# --------------------------------------------------------------------------

def chamar_modelo_stream(client: OpenAI, mensagens: list[dict], contador: ContadorTokens):
    """
    Faz uma chamada ao modelo em streaming, imprimindo o texto conforme chega.
    Devolve (conteudo_completo, tool_calls, usage) -- tool_calls é uma lista no
    formato que a API espera (pronta para reenviar em 'messages'), ou [] se o
    modelo respondeu só com texto.
    """
    try:
        stream = client.chat.completions.create(
            model=JANAS_MODEL,
            messages=mensagens,
            tools=TOOLS,
            tool_choice="auto",
            temperature=0.7,
            stream=True,
            stream_options={"include_usage": True},
            extra_body=extra_body_reasoning(),
        )
    except Exception:
        # Servidor não aceitou streaming (ou alguma opção) -- tenta sem stream.
        return _chamar_modelo_sem_stream(client, mensagens, contador)

    buffer = []
    tool_calls_acc: dict[int, dict] = {}
    usage = None
    algo_impresso = False

    for chunk in stream:
        if not chunk.choices:
            if getattr(chunk, "usage", None):
                usage = chunk.usage
            continue

        delta = chunk.choices[0].delta

        if delta and delta.content:
            print(delta.content, end="", flush=True)
            buffer.append(delta.content)
            algo_impresso = True

        if delta and delta.tool_calls:
            for tc in delta.tool_calls:
                entry = tool_calls_acc.setdefault(
                    tc.index,
                    {"id": None, "type": "function", "function": {"name": "", "arguments": ""}},
                )
                if tc.id:
                    entry["id"] = tc.id
                if tc.function:
                    if tc.function.name:
                        entry["function"]["name"] += tc.function.name
                    if tc.function.arguments:
                        entry["function"]["arguments"] += tc.function.arguments

        if getattr(chunk, "usage", None):
            usage = chunk.usage

    if algo_impresso:
        print()  # fecha a linha depois do texto em streaming

    tool_calls = [tool_calls_acc[i] for i in sorted(tool_calls_acc)]
    conteudo = "".join(buffer)
    contador.registrar(usage)
    return conteudo, tool_calls, usage


def _chamar_modelo_sem_stream(client: OpenAI, mensagens: list[dict], contador: ContadorTokens):
    """Caminho alternativo caso o streaming falhe."""
    resposta = client.chat.completions.create(
        model=JANAS_MODEL,
        messages=mensagens,
        tools=TOOLS,
        tool_choice="auto",
        temperature=0.7,
        extra_body=extra_body_reasoning(),
    )
    msg = resposta.choices[0].message
    conteudo = msg.content or ""
    if conteudo:
        print(conteudo)
    tool_calls = []
    if msg.tool_calls:
        for tc in msg.tool_calls:
            tool_calls.append(
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                }
            )
    contador.registrar(resposta.usage)
    return conteudo, tool_calls, resposta.usage


# --------------------------------------------------------------------------
# Laço do agente
# --------------------------------------------------------------------------

def responder(client: OpenAI, mensagens: list[dict], contador: ContadorTokens) -> str:
    for rodada in range(MAX_TOOL_ROUNDS):
        conteudo, tool_calls, _usage = chamar_modelo_stream(client, mensagens, contador)

        if not tool_calls:
            return conteudo

        # Registra a mensagem do assistente (com as chamadas de ferramenta pedidas)
        mensagens.append(
            {
                "role": "assistant",
                "content": conteudo or None,
                "tool_calls": tool_calls,
            }
        )

        for chamada in tool_calls:
            try:
                args = json.loads(chamada["function"]["arguments"] or "{}")
            except json.JSONDecodeError:
                args = {}
            consulta = args.get("query", "")
            print(f"[buscando na internet: {consulta}]", flush=True)
            resultado = executar_ferramenta(chamada["function"]["name"], args)
            mensagens.append(
                {
                    "role": "tool",
                    "tool_call_id": chamada["id"],
                    "content": resultado,
                }
            )
        # volta pro topo do loop para o modelo ler o resultado da ferramenta

    return (
        "O modelo pediu ferramentas demais em sequência para essa pergunta; "
        "parei por segurança. Tente reformular a pergunta."
    )


def main() -> None:
    client = OpenAI(base_url=JANAS_BASE_URL, api_key=JANAS_API_KEY)
    contador = ContadorTokens()

    mensagens: list[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]

    print(f"Conectando no Janas em {JANAS_BASE_URL} (modelo: {JANAS_MODEL}, reasoning: {JANAS_THINK})")
    print("Digite sua pergunta. Comandos: 'sair' para encerrar, 'limpar' para reiniciar a conversa.\n")

    while True:
        try:
            entrada = input("Você: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not entrada:
            continue
        if entrada.lower() in {"sair", "exit", "quit"}:
            break
        if entrada.lower() == "limpar":
            mensagens = [{"role": "system", "content": SYSTEM_PROMPT}]
            print("(conversa reiniciada; contador de tokens da sessão continua somando)\n")
            continue

        mensagens.append({"role": "user", "content": entrada})

        prompt_antes = contador.prompt_total
        completion_antes = contador.completion_total

        print("Janas: ", end="", flush=True)
        try:
            resposta = responder(client, mensagens, contador)
        except Exception as exc:
            print(f"\n[erro ao falar com o Janas: {exc}]\n", file=sys.stderr)
            mensagens.pop()  # remove a pergunta que não foi respondida
            continue

        mensagens.append({"role": "assistant", "content": resposta})

        prompt_turno = contador.prompt_total - prompt_antes
        completion_turno = contador.completion_total - completion_antes
        print(
            f"\n[turno: {prompt_turno + completion_turno} tokens "
            f"(prompt {prompt_turno} + resposta {completion_turno}) | {contador.resumo_sessao()}]\n"
        )


if __name__ == "__main__":
    main()
