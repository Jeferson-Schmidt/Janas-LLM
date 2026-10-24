"""
Interface web do agente (http://127.0.0.1:8090).

Acesso protegido por token (ver config.get_access_token):
  - abra http://127.0.0.1:8090/?token=SEU_TOKEN uma vez, ou digite o token
    na tela de login; o navegador guarda um cookie e a URL fica limpa;
  - chamadas à API sem o cookie (ou sem "Authorization: Bearer SEU_TOKEN")
    recebem 401;
  - depois de 10 tentativas erradas, o IP fica bloqueado por 10 minutos.

Cada navegador tem a sua conversa (cookie janas_agent_sid).
"""

from __future__ import annotations

import asyncio
import hmac
import json
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response, StreamingResponse

import config
import scraper
from agent_core import run_turn, sessions
from janas_client import main_client

ACCESS_TOKEN = config.get_access_token()
AUTH_COOKIE = "janas_agent_auth"
SID_COOKIE = "janas_agent_sid"
STATIC_DIR = Path(__file__).resolve().parent / "static"

_falhas: dict[str, list[float]] = {}


@asynccontextmanager
async def lifespan(_app: FastAPI):
    yield
    await scraper.close()


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


# --------------------------------------------------------------------------
# Autenticação
# --------------------------------------------------------------------------

def _ip(request: Request) -> str:
    # Pelo túnel do cloudflared o IP real vem neste cabeçalho.
    return request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "?")


def _bloqueado(ip: str) -> bool:
    recentes = [t for t in _falhas.get(ip, []) if time.time() - t < 600]
    _falhas[ip] = recentes
    return len(recentes) >= 10


def _token_ok(valor: str | None) -> bool:
    return bool(valor) and hmac.compare_digest(valor.encode(), ACCESS_TOKEN.encode())


def _autenticado(request: Request) -> bool:
    if _token_ok(request.cookies.get(AUTH_COOKIE)):
        return True
    auth = request.headers.get("authorization", "")
    return auth.lower().startswith("bearer ") and _token_ok(auth[7:].strip())


def _https(request: Request) -> bool:
    return request.url.scheme == "https" or request.headers.get("x-forwarded-proto") == "https"


def _set_cookie(resp: Response, request: Request, nome: str, valor: str) -> None:
    resp.set_cookie(nome, valor, max_age=30 * 24 * 3600, httponly=True, samesite="lax", secure=_https(request))


def _login_page(erro: str = "") -> HTMLResponse:
    html = (STATIC_DIR / "login.html").read_text(encoding="utf-8")
    return HTMLResponse(html.replace("{{ERRO}}", erro), status_code=401 if erro else 200)


@app.middleware("http")
async def autenticacao(request: Request, call_next):
    caminho = request.url.path
    if caminho in ("/login", "/favicon.ico"):
        return await call_next(request)

    ip = _ip(request)
    token_url = request.query_params.get("token")
    if token_url is not None:
        if _bloqueado(ip):
            return _login_page("Muitas tentativas. Aguarde 10 minutos.")
        if _token_ok(token_url):
            resp = RedirectResponse("/", status_code=303)
            _set_cookie(resp, request, AUTH_COOKIE, ACCESS_TOKEN)
            return resp
        _falhas.setdefault(ip, []).append(time.time())
        return _login_page("Token inválido.")

    if not _autenticado(request):
        if caminho.startswith("/api/"):
            return JSONResponse({"error": "não autorizado"}, status_code=401)
        return _login_page()

    resp = await call_next(request)
    if not request.cookies.get(SID_COOKIE) and getattr(request.state, "sid", None):
        _set_cookie(resp, request, SID_COOKIE, request.state.sid)
    return resp


@app.post("/login")
async def login(request: Request):
    ip = _ip(request)
    if _bloqueado(ip):
        return _login_page("Muitas tentativas. Aguarde 10 minutos.")
    form = (await request.body()).decode()
    from urllib.parse import parse_qs

    token = (parse_qs(form).get("token") or [""])[0].strip()
    if not _token_ok(token):
        _falhas.setdefault(ip, []).append(time.time())
        return _login_page("Token inválido.")
    resp = RedirectResponse("/", status_code=303)
    _set_cookie(resp, request, AUTH_COOKIE, ACCESS_TOKEN)
    return resp


@app.get("/login")
async def login_get():
    return _login_page()


# --------------------------------------------------------------------------
# Páginas e API
# --------------------------------------------------------------------------

async def _json(request: Request) -> dict:
    try:
        dados = await request.json()
    except (ValueError, UnicodeDecodeError):
        return {}
    return dados if isinstance(dados, dict) else {}


def _sessao(request: Request):
    sess = sessions.get(request.cookies.get(SID_COOKIE))
    request.state.sid = sess.id
    return sess


@app.get("/")
async def index(request: Request):
    _sessao(request)
    return HTMLResponse((STATIC_DIR / "index.html").read_text(encoding="utf-8"),
                        headers={"Cache-Control": "no-store"})


@app.get("/api/state")
async def state(request: Request):
    sess = _sessao(request)
    saude = await main_client.health()
    return {**sess.state(), "server": saude, "config": {
        "pages_per_search": config.PAGES_PER_SEARCH,
        "context_window": config.CONTEXT_WINDOW,
        "dynamic": config.DYNAMIC_ENABLED,
    }}


@app.post("/api/settings")
async def settings(request: Request):
    sess = _sessao(request)
    dados = await _json(request)
    if "think" in dados:
        sess.think = bool(dados["think"])
    return sess.state()


@app.post("/api/reset")
async def reset(request: Request):
    sess = _sessao(request)
    if sess.busy:
        return JSONResponse({"error": "aguarde a resposta atual terminar ou clique em Parar"}, status_code=409)
    sess.reset()
    return sess.state()


@app.post("/api/stop")
async def stop(request: Request):
    _sessao(request).cancel.set()
    return {"ok": True}


@app.post("/api/chat")
async def chat(request: Request):
    sess = _sessao(request)
    dados = await _json(request)
    pergunta = (dados.get("message") or "").strip()
    if not pergunta:
        return JSONResponse({"error": "mensagem vazia"}, status_code=400)
    if sess.busy:
        return JSONResponse({"error": "esta conversa já está gerando uma resposta"}, status_code=409)

    fila: asyncio.Queue = asyncio.Queue()

    async def emit(evento: dict) -> None:
        await fila.put(evento)

    async def turno():
        try:
            await run_turn(sess, pergunta, emit)
        except Exception as exc:  # garantia: o navegador sempre recebe um fim
            await fila.put({"type": "error", "text": f"erro interno: {exc}"})
        finally:
            await fila.put(None)

    # O turno roda independente da conexão: se o navegador fechar ou a rede
    # cair, a resposta termina e aparece no histórico ao recarregar a página.
    sess.busy = True
    asyncio.create_task(turno())

    async def eventos():
        while True:
            try:
                evento = await asyncio.wait_for(fila.get(), timeout=15)
            except asyncio.TimeoutError:
                # Mantém a conexão viva durante prompts longos (o túnel do
                # cloudflared derruba conexões paradas por ~100 s).
                yield ": ping\n\n"
                continue
            if evento is None:
                break
            yield f"data: {json.dumps(evento, ensure_ascii=False)}\n\n"

    return StreamingResponse(eventos(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print(f"Agente Janas v2 em http://{config.AGENT_HOST}:{config.AGENT_PORT}")
    print(f"janas-server esperado em {config.JANAS_BASE_URL}")
    print(f"Token de acesso: {ACCESS_TOKEN}")
    print(f"Link direto (local): http://127.0.0.1:{config.AGENT_PORT}/?token={ACCESS_TOKEN}")
    print("Pelo túnel: https://<seu-endereço>.trycloudflare.com/?token=<token acima>\n")
    uvicorn.run(app, host=config.AGENT_HOST, port=config.AGENT_PORT, log_level="warning")


if __name__ == "__main__":
    main()
