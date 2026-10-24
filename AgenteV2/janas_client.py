"""
Conexão com o janas-server, que roda em outro terminal (run-chat-web.ps1).

  - Descobre sozinho qual modelo o servidor carregou (GET /v1/models), então
    trocar entre 35B e 80B no outro terminal não exige mudar nada aqui.
  - Lê o uso de tokens de cada resposta, incluindo o objeto "janas" que o
    servidor acrescenta ao usage (contexto usado e tamanho real do contexto).
  - Serializa as chamadas: o servidor atende uma por vez, então o agente
    mostra "na fila" em vez de várias conversas disputando o modelo.
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field

from openai import AsyncOpenAI

import config


@dataclass
class Usage:
    prompt: int = 0          # tokens do prompt (inclui os que já estavam em cache)
    cached: int = 0          # tokens do prompt reaproveitados do cache do servidor
    completion: int = 0      # tokens gerados
    context_used: int = 0    # contexto ocupado ao fim da chamada
    context_size: int = 0    # contexto do servidor (--ctx)
    prompt_seconds: float = 0.0
    gen_seconds: float = 0.0
    raw: dict = field(default_factory=dict)

    @property
    def new_prompt(self) -> int:
        """Tokens de prompt que o servidor de fato teve que ler agora."""
        return max(self.prompt - self.cached, 0)

    def as_dict(self) -> dict:
        return {
            "prompt": self.prompt,
            "cached": self.cached,
            "new_prompt": self.new_prompt,
            "completion": self.completion,
            "context_used": self.context_used,
            "context_size": self.context_size,
            "prompt_seconds": round(self.prompt_seconds, 2),
            "gen_seconds": round(self.gen_seconds, 2),
        }


def _first_number(d: dict, *nomes: str):
    for nome in nomes:
        valor = d.get(nome)
        if isinstance(valor, (int, float)):
            return valor
    return None


def parse_usage(usage) -> Usage:
    if usage is None:
        return Usage()
    d = usage.model_dump() if hasattr(usage, "model_dump") else dict(usage)
    u = Usage(raw=d)
    u.prompt = d.get("prompt_tokens") or 0
    u.completion = d.get("completion_tokens") or 0
    detalhes = d.get("prompt_tokens_details") or {}
    u.cached = detalhes.get("cached_tokens") or 0

    janas = d.get("janas") or {}
    if isinstance(janas, dict):
        # Formato do janas-server v2026.10.14:
        # {"context_used", "context_size", "input_seconds", "output_seconds"}
        u.context_used = int(_first_number(janas, "context_used") or 0)
        u.context_size = int(_first_number(janas, "context_size") or 0)
        u.prompt_seconds = float(_first_number(janas, "input_seconds") or 0)
        u.gen_seconds = float(_first_number(janas, "output_seconds") or 0)
    if not u.context_used:
        u.context_used = u.prompt + u.completion
    return u


# --------------------------------------------------------------------------
# Contadores de tokens e velocidade
# --------------------------------------------------------------------------

def new_counter() -> dict:
    return {
        "new_prompt": 0, "cached": 0, "completion": 0,
        "input_seconds": 0.0, "output_seconds": 0.0, "calls": 0,
        # Velocidade: só chamadas grandes o bastante (config.RATE_MIN_*), porque
        # numa leitura de poucos tokens o custo fixo da chamada domina e a
        # taxa sai artificialmente baixa.
        "rate_read_tokens": 0, "rate_read_seconds": 0.0,
        "rate_gen_tokens": 0, "rate_gen_seconds": 0.0,
    }


def add_usage(contador: dict, uso: dict) -> None:
    """Soma o uso de uma chamada (Usage.as_dict()) ao contador."""
    lidos, segundos_leitura = uso.get("new_prompt", 0), uso.get("prompt_seconds", 0)
    gerados, segundos_geracao = uso.get("completion", 0), uso.get("gen_seconds", 0)
    contador["new_prompt"] += lidos
    contador["cached"] += uso.get("cached", 0)
    contador["completion"] += gerados
    contador["input_seconds"] = round(contador["input_seconds"] + segundos_leitura, 2)
    contador["output_seconds"] = round(contador["output_seconds"] + segundos_geracao, 2)
    contador["calls"] += 1
    if lidos >= config.RATE_MIN_READ_TOKENS and segundos_leitura > 0:
        contador["rate_read_tokens"] += lidos
        contador["rate_read_seconds"] = round(contador["rate_read_seconds"] + segundos_leitura, 2)
    if gerados >= config.RATE_MIN_GEN_TOKENS and segundos_geracao > 0:
        contador["rate_gen_tokens"] += gerados
        contador["rate_gen_seconds"] = round(contador["rate_gen_seconds"] + segundos_geracao, 2)


def merge_counter(destino: dict, origem: dict) -> None:
    for chave, valor in origem.items():
        destino[chave] = round(destino.get(chave, 0) + valor, 2) if isinstance(valor, float) else destino.get(chave, 0) + valor


class ModelStats:
    """
    Velocidade acumulada por modelo, somando todas as conversas, para comparar
    o 35B com o 80B. Fica em .stats.json, então sobrevive a reinícios do
    agente e só zera pelo botão da interface.
    """

    def __init__(self, caminho) -> None:
        self.caminho = caminho
        self.dados = {"since": time.time(), "models": {}}
        try:
            self.dados = json.loads(caminho.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass

    def record(self, modelo: str, tipo: str, uso: dict) -> None:
        if not modelo:
            return
        por_modelo = self.dados["models"].setdefault(modelo, {"conversa": new_counter(), "resumos": new_counter()})
        add_usage(por_modelo.setdefault(tipo, new_counter()), uso)
        self._save()

    def reset(self) -> None:
        self.dados = {"since": time.time(), "models": {}}
        self._save()

    def _save(self) -> None:
        try:
            self.caminho.write_text(json.dumps(self.dados), encoding="utf-8")
        except OSError:
            pass  # sem disco, as estatísticas continuam valendo até reiniciar


model_stats = ModelStats(config.STATS_FILE)


def reasoning_body(think: bool) -> dict:
    """Liga/desliga o raciocínio do modelo por requisição (sem reiniciar o servidor)."""
    return {
        "reasoning_effort": "medium" if think else "none",
        "chat_template_kwargs": {"enable_thinking": think},
    }


class JanasClient:
    def __init__(self, base_url: str, model: str = "") -> None:
        self.base_url = base_url
        self.api = AsyncOpenAI(
            base_url=base_url,
            api_key=config.JANAS_API_KEY,
            timeout=config.MODEL_TIMEOUT_SECONDS,
            max_retries=0,
        )
        self._fixed_model = model
        self.model = model
        self.context_size = 0  # aprendido das respostas do servidor
        self.lock = asyncio.Lock()
        self.waiting = 0

    async def discover_model(self) -> str:
        if self._fixed_model:
            return self._fixed_model
        modelos = await self.api.models.list()
        ids = [m.id for m in modelos.data]
        if not ids:
            raise RuntimeError("o janas-server não informou nenhum modelo")
        self.model = ids[0]
        return self.model

    async def health(self) -> dict:
        try:
            modelo = await asyncio.wait_for(self.discover_model(), timeout=3)
            return {"online": True, "model": modelo, "base_url": self.base_url}
        except Exception as exc:
            return {"online": False, "model": self.model, "base_url": self.base_url,
                    "error": str(exc) or type(exc).__name__}

    def learn(self, usage: Usage) -> None:
        if usage.context_size:
            self.context_size = usage.context_size

    @property
    def display_model(self) -> str:
        """O id vem como caminho do arquivo (D:\\...\\qwen3.6-35b-a3b-q4km); mostra só o nome."""
        return self.model.replace("\\", "/").rsplit("/", 1)[-1] if self.model else ""

    @property
    def effective_context(self) -> int:
        if self.context_size:
            return min(config.CONTEXT_WINDOW, self.context_size)
        return config.CONTEXT_WINDOW


main_client = JanasClient(config.JANAS_BASE_URL, config.JANAS_MODEL)
if config.SUMMARY_BASE_URL == config.JANAS_BASE_URL and not config.SUMMARY_MODEL:
    summary_client = main_client
else:
    summary_client = JanasClient(config.SUMMARY_BASE_URL, config.SUMMARY_MODEL)
