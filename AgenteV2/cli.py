"""
Agente Janas v2 no terminal. Mesmo núcleo da interface web (agent_core).

Comandos: 'sair' encerra, 'limpar' reinicia a conversa, 'pensar' liga/desliga
o raciocínio.
"""

from __future__ import annotations

import asyncio
import sys

import config
import scraper
from agent_core import Session, run_turn
from janas_client import main_client


def _fmt(n: int) -> str:
    return f"{n:,}".replace(",", ".")


async def emit(evento: dict) -> None:
    tipo = evento["type"]
    if tipo == "delta":
        print(evento["text"], end="", flush=True)
    elif tipo == "reasoning":
        print(f"\033[2m{evento['text']}\033[0m", end="", flush=True)
    elif tipo in ("status", "tool"):
        acao = "Abrindo" if evento.get("kind") == "url" else "Pesquisando"
        texto = evento.get("text") or f"{acao}: {evento['query']}"
        print(f"\033[2m  · {texto}\033[0m", flush=True)
    elif tipo == "page":
        print(f"\033[2m    [{evento['n']}] {evento['url']} ({evento['method']}, {_fmt(evento['chars'])} car.)\033[0m")
    elif tipo == "compacted":
        print("\033[33m  · contexto compactado\033[0m")
    elif tipo == "error":
        print(f"\n\033[31m[{evento['text']}]\033[0m", file=sys.stderr)
    elif tipo == "done":
        u, st = evento["usage"], evento["state"]
        c, r = u["conversa"], u["resumos"]
        ctx = st["context"]
        linha = (f"\n\033[2m[{u['seconds']} s | lidos {_fmt(c['new_prompt'])} (cache {_fmt(c['cached'])}) "
                 f"gerados {_fmt(c['completion'])}")
        if r["calls"]:
            linha += f" | resumos {_fmt(r['new_prompt'])}→{_fmt(r['completion'])}"
        for nome, tok, seg in (("leitura", "rate_read_tokens", "rate_read_seconds"),
                               ("geração", "rate_gen_tokens", "rate_gen_seconds")):
            segundos = c[seg] + r[seg]
            if segundos > 0:
                linha += f" | {nome} {(c[tok] + r[tok]) / segundos:.1f} tok/s"
        linha += f" | contexto {_fmt(ctx['used'])}/{_fmt(ctx['limit'])}]\033[0m\n"
        print(linha)


async def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    saude = await main_client.health()
    if not saude["online"]:
        print(f"janas-server offline em {config.JANAS_BASE_URL}: {saude.get('error')}")
        print("Inicie-o em outro terminal com .\\scripts\\run-chat-web.ps1 e tente de novo.")
        return
    sessao = Session(id="cli")
    print(f"Conectado: {main_client.display_model} em {config.JANAS_BASE_URL}")
    print("Comandos: 'sair', 'limpar', 'pensar' (liga/desliga raciocínio).\n")
    try:
        while True:
            try:
                entrada = (await asyncio.to_thread(input, "Você: ")).strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not entrada:
                continue
            comando = entrada.lower()
            if comando in ("sair", "exit", "quit"):
                break
            if comando == "limpar":
                sessao.reset()
                print("(conversa reiniciada)\n")
                continue
            if comando == "pensar":
                sessao.think = not sessao.think
                print(f"(raciocínio {'ligado' if sessao.think else 'desligado'})\n")
                continue
            print("Janas: ", end="", flush=True)
            try:
                await run_turn(sessao, entrada, emit)
            except KeyboardInterrupt:
                sessao.cancel.set()
    finally:
        await scraper.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
