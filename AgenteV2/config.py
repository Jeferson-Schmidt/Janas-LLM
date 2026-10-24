"""
Configuração do agente Janas v2. Tudo que vale a pena ajustar fica aqui.

Cada valor pode ser trocado editando este arquivo ou, quando indicado, por
variável de ambiente (útil para não editar código).
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parent


def _env_int(nome: str, padrao: int) -> int:
    try:
        return int(os.environ.get(nome, padrao))
    except ValueError:
        return padrao


# --------------------------------------------------------------------------
# Contexto e tokens
# --------------------------------------------------------------------------

# Tamanho de contexto que o agente considera disponível. Se o janas-server
# foi iniciado com um --ctx menor, o agente usa o menor dos dois (o servidor
# informa o tamanho real em cada resposta).
CONTEXT_WINDOW = _env_int("JANAS_CONTEXT_WINDOW", 65535)

# Ao passar desta fração do contexto, a conversa é compactada automaticamente
# (o modelo resume a conversa e ela recomeça a partir do resumo).
COMPACT_AT = 0.85

# Máximo de tokens que a resposta final pode gerar e que o resumo da
# compactação pode ter.
ANSWER_MAX_TOKENS = 1500
COMPACT_MAX_TOKENS = 700

TEMPERATURE = 0.3

# Raciocínio (reasoning) ligado por padrão? Pode ser trocado pela interface.
THINK_DEFAULT = os.environ.get("JANAS_THINK", "off").strip().lower() == "on"

# Trava de segurança: chamadas de ferramenta seguidas por pergunta.
MAX_TOOL_ROUNDS = 3


# --------------------------------------------------------------------------
# Conexão com o janas-server (rodando em outro terminal)
# --------------------------------------------------------------------------

JANAS_BASE_URL = os.environ.get("JANAS_BASE_URL", "http://127.0.0.1:8080/v1")
JANAS_API_KEY = os.environ.get("JANAS_API_KEY", "not-needed")

# Vazio = descobre sozinho pelo GET /v1/models (o modelo que o servidor carregou).
JANAS_MODEL = os.environ.get("JANAS_MODEL", "")

# Opcional: outro servidor só para os resumos de página. Vazio = o mesmo.
SUMMARY_BASE_URL = os.environ.get("JANAS_SUMMARY_BASE_URL", "") or JANAS_BASE_URL
SUMMARY_MODEL = os.environ.get("JANAS_SUMMARY_MODEL", "")

# Tempo máximo esperando o modelo (CPU com prompt longo pode demorar).
MODEL_TIMEOUT_SECONDS = 900


# --------------------------------------------------------------------------
# Pesquisa e scraping
# --------------------------------------------------------------------------

PAGES_PER_SEARCH = 3        # páginas lidas e resumidas por pesquisa (mínimo pedido: 3)
SEARCH_RESULTS = 8          # resultados pedidos à busca (sobra para quando uma página falha)
SEARCH_REGION = "br-pt"     # região do DuckDuckGo ("wt-wt" = sem região)
SEARCH_TIMEOUT_SECONDS = 10

FETCH_TIMEOUT_SECONDS = 12
FETCH_MAX_BYTES = 3_000_000  # páginas maiores são cortadas no download

# Se o texto extraído da versão estática tiver menos que isso, a página é
# considerada dinâmica (montada por JavaScript) e é aberta no Chromium.
DYNAMIC_MIN_CHARS = 800
DYNAMIC_ENABLED = True
DYNAMIC_TIMEOUT_SECONDS = 20

# Filtro feito sem LLM antes do resumo: a página é quebrada em trechos e só
# os trechos mais relevantes para a pergunta vão para o modelo.
CHUNK_CHARS = 700
CHARS_PER_PAGE = 3000       # ~800 tokens por página enviados ao resumo

# True: as páginas filtradas são resumidas numa chamada à parte e só o resumo
# entra na conversa (ocupa pouco contexto). False ("modo direto"): os trechos
# filtrados entram direto na conversa, sem a chamada de resumo. Medido neste
# PC (35B, CPU), o modo direto economiza ~30-40 s por pesquisa, porque o
# resumo precisa ler as páginas E escrever o resumo (geração ~10 tok/s), mas
# ocupa ~4x mais contexto por pesquisa.
SUMMARIZE_PAGES = True

SUMMARY_MAX_TOKENS = 350
SUMMARY_TEMPERATURE = 0.1

# Ferramenta fetch_url (link passado pelo usuário): o texto do endereço entra
# direto na conversa, sem resumo. Acima deste tamanho, só os trechos mais
# relevantes para a pergunta (~4 mil tokens no limite).
FETCH_URL_MAX_CHARS = 16000

# Páginas já baixadas e pesquisas já resumidas ficam em cache por este tempo.
CACHE_TTL_SECONDS = 3600


# --------------------------------------------------------------------------
# Interface web e acesso externo
# --------------------------------------------------------------------------

# 127.0.0.1 basta para o cloudflared (ele roda neste mesmo PC). Use 0.0.0.0
# só se quiser acessar diretamente de outro aparelho da rede local.
AGENT_HOST = os.environ.get("JANAS_AGENT_HOST", "127.0.0.1")
AGENT_PORT = _env_int("JANAS_AGENT_PORT", 8090)

# Uma conversa por navegador; conversas paradas por mais tempo que isso são
# descartadas. O limite acompanha o --keep 8 padrão do janas-server, que
# mantém em cache até 8 conversas além da atual.
MAX_SESSIONS = 8
SESSION_IDLE_SECONDS = 6 * 3600

TOKEN_FILE = AGENT_DIR / ".token"


def get_access_token() -> str:
    """
    Token de acesso da interface web.

    Ordem: variável de ambiente JANAS_AGENT_TOKEN; senão o arquivo .token
    desta pasta; senão gera um token aleatório e grava em .token.
    Para trocar o token, apague o .token (ou defina a variável) e reinicie.
    """
    token = os.environ.get("JANAS_AGENT_TOKEN", "").strip()
    if token:
        return token
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()
        if token:
            return token
    token = secrets.token_urlsafe(32)
    TOKEN_FILE.write_text(token, encoding="utf-8")
    return token
