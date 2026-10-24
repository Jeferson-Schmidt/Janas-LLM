"""
Download e extração de texto de páginas web.

  - Estáticas: httpx + trafilatura (extrai só o texto principal, sem menu,
    rodapé e anúncios).
  - Dinâmicas (montadas por JavaScript): Chromium headless via Playwright,
    usado apenas quando a versão estática traz pouco texto.

Toda URL passa por url_is_public(): endereços locais e de rede interna são
recusados, inclusive em redirecionamentos, para que ninguém com acesso à
interface possa usar o agente para ler 127.0.0.1:8080 ou a rede da casa.
"""

from __future__ import annotations

import asyncio
import ipaddress
import socket
import ssl
import sys
import threading
import time
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx
import trafilatura
import truststore

import config

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)


@dataclass
class Page:
    url: str
    text: str = ""
    method: str = ""       # "estática", "dinâmica" ou "cache"
    error: str = ""
    seconds: float = 0.0


# --------------------------------------------------------------------------
# Proteção contra acesso a endereços internos
# --------------------------------------------------------------------------

def url_is_public(url: str) -> bool:
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        return False
    try:
        infos = socket.getaddrinfo(parsed.hostname, parsed.port or 443, proto=socket.IPPROTO_TCP)
    except OSError:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0].split("%")[0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved
                or ip.is_multicast or ip.is_unspecified):
            return False
    return True


async def _check_request(request: httpx.Request) -> None:
    # Roda em toda requisição do httpx, incluindo cada redirecionamento.
    if not await asyncio.to_thread(url_is_public, str(request.url)):
        raise httpx.RequestError(f"endereço não público recusado: {request.url.host}")


# --------------------------------------------------------------------------
# Extração de texto
# --------------------------------------------------------------------------

def extract_text(html: str, url: str) -> str:
    text = trafilatura.extract(
        html,
        url=url,
        include_comments=False,
        include_tables=True,
        favor_recall=True,
        deduplicate=True,
    )
    return (text or "").strip()


# --------------------------------------------------------------------------
# Páginas estáticas
# --------------------------------------------------------------------------

_http_client: httpx.AsyncClient | None = None


def _client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None:
        _http_client = httpx.AsyncClient(
            follow_redirects=True,
            max_redirects=5,
            timeout=config.FETCH_TIMEOUT_SECONDS,
            headers={"User-Agent": USER_AGENT, "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8"},
            event_hooks={"request": [_check_request]},
            # Certificados do repositório do Windows: funciona com antivírus
            # que inspecionam HTTPS (o Avast desta máquina reassina tudo).
            verify=truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT),
        )
    return _http_client


async def fetch_static(url: str) -> Page:
    inicio = time.perf_counter()
    try:
        async with _client().stream("GET", url) as resp:
            if resp.status_code >= 400:
                return Page(url, error=f"HTTP {resp.status_code}", method="estática")
            tipo = resp.headers.get("content-type", "")
            if tipo and "html" not in tipo and "text" not in tipo:
                return Page(url, error=f"tipo não suportado ({tipo.split(';')[0]})", method="estática")
            partes, total = [], 0
            async for bloco in resp.aiter_bytes():
                partes.append(bloco)
                total += len(bloco)
                if total >= config.FETCH_MAX_BYTES:
                    break
            html = b"".join(partes).decode(resp.encoding or "utf-8", errors="replace")
    except Exception as exc:
        return Page(url, error=str(exc) or type(exc).__name__, method="estática",
                    seconds=time.perf_counter() - inicio)

    text = await asyncio.to_thread(extract_text, html, url)
    return Page(url, text=text, method="estática", seconds=time.perf_counter() - inicio)


# --------------------------------------------------------------------------
# Páginas dinâmicas (Chromium headless)
# --------------------------------------------------------------------------

class DynamicRenderer:
    """
    Mantém um Chromium aberto numa thread própria, com seu próprio event loop.

    Fica separado do loop do servidor web porque, no Windows, o Playwright
    precisa de um loop que suporte subprocessos, e o uvicorn pode usar outro
    tipo. O navegador só abre na primeira página dinâmica e depois é reusado.
    """

    def __init__(self) -> None:
        self._loop: asyncio.AbstractEventLoop | None = None
        self._browser = None
        self._playwright = None
        self._start_lock = threading.Lock()
        self.unavailable_reason = ""

    def _ensure_loop(self) -> asyncio.AbstractEventLoop:
        with self._start_lock:
            if self._loop is None:
                if sys.platform == "win32":
                    loop = asyncio.ProactorEventLoop()
                else:
                    loop = asyncio.new_event_loop()
                threading.Thread(target=loop.run_forever, name="playwright", daemon=True).start()
                self._loop = loop
            return self._loop

    async def _get_browser(self):
        if self._browser is None or not self._browser.is_connected():
            from playwright.async_api import async_playwright

            if self._playwright is None:
                self._playwright = await async_playwright().start()
            self._browser = await self._playwright.chromium.launch(headless=True)
        return self._browser

    async def _render(self, url: str) -> str:
        browser = await self._get_browser()
        context = await browser.new_context(user_agent=USER_AGENT, locale="pt-BR")
        try:
            page = await context.new_page()

            async def filtrar(route):
                req = route.request
                # Imagens, fontes e mídia não ajudam a extrair texto: só atrasam.
                if req.resource_type in ("image", "media", "font"):
                    await route.abort()
                elif not await asyncio.to_thread(url_is_public, req.url):
                    await route.abort()
                else:
                    await route.continue_()

            await page.route("**/*", filtrar)
            timeout_ms = config.DYNAMIC_TIMEOUT_SECONDS * 1000
            await page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
            try:
                await page.wait_for_load_state("networkidle", timeout=5000)
            except Exception:
                pass  # sites com conexões abertas para sempre: segue com o que já carregou
            return await page.content()
        finally:
            await context.close()

    async def fetch(self, url: str) -> Page:
        inicio = time.perf_counter()
        if self.unavailable_reason:
            return Page(url, error=self.unavailable_reason, method="dinâmica")
        try:
            loop = self._ensure_loop()
            futuro = asyncio.run_coroutine_threadsafe(self._render(url), loop)
            html = await asyncio.wait_for(
                asyncio.wrap_future(futuro), timeout=config.DYNAMIC_TIMEOUT_SECONDS + 10
            )
        except ImportError:
            self.unavailable_reason = "Playwright não instalado (rode setup-agent.ps1)"
            return Page(url, error=self.unavailable_reason, method="dinâmica")
        except Exception as exc:
            mensagem = str(exc).splitlines()[0] if str(exc) else type(exc).__name__
            if "Executable doesn't exist" in mensagem:
                self.unavailable_reason = "Chromium do Playwright não instalado (rode setup-agent.ps1)"
                mensagem = self.unavailable_reason
            return Page(url, error=mensagem, method="dinâmica", seconds=time.perf_counter() - inicio)

        text = await asyncio.to_thread(extract_text, html, url)
        return Page(url, text=text, method="dinâmica", seconds=time.perf_counter() - inicio)

    def close(self) -> None:
        if self._loop is None:
            return

        async def _fechar():
            if self._browser is not None:
                await self._browser.close()
            if self._playwright is not None:
                await self._playwright.stop()

        try:
            asyncio.run_coroutine_threadsafe(_fechar(), self._loop).result(timeout=10)
        except Exception:
            pass
        self._loop.call_soon_threadsafe(self._loop.stop)


renderer = DynamicRenderer()


# --------------------------------------------------------------------------
# Cache de páginas (compartilhado entre conversas: é conteúdo público)
# --------------------------------------------------------------------------

_page_cache: dict[str, tuple[float, str]] = {}


def cached_text(url: str) -> str | None:
    item = _page_cache.get(url)
    if item and time.time() - item[0] < config.CACHE_TTL_SECONDS:
        return item[1]
    return None


def store_text(url: str, text: str) -> None:
    _page_cache[url] = (time.time(), text)
    if len(_page_cache) > 500:
        for chave, _ in sorted(_page_cache.items(), key=lambda kv: kv[1][0])[:100]:
            _page_cache.pop(chave, None)


async def close() -> None:
    global _http_client
    if _http_client is not None:
        await _http_client.aclose()
        _http_client = None
    await asyncio.to_thread(renderer.close)
