# Spec: Janas LLM

Memória do trabalho neste projeto. Leia antes de agir e atualize ao terminar cada etapa. A infraestrutura está em [infra.md](infra.md).

Última atualização: 2026-11-05

## Objetivo

Rodar modelos grandes localmente com o Janas neste PC, medir o desempenho e usá-los por meio do AgenteV2 e do Cline, sem custo de API.

## Onde estamos

Ambiente restaurado depois da perda de arquivos de 31/10. Os dois modelos e o AgenteV2 funcionam em CPU com o Janas v2026.11.04. Próxima etapa: decidir o contexto padrão.

## Feito

- [x] Janas atualizado para a v2026.11.04 (pacote completo em `bin/janas/`).
- [x] Modelo 80B com bloco MTP em `models/`: ~20 tok/s de geração em CPU, contra ~16 sem o bloco.
- [x] Modelo 35B baixado de novo: ~16 tok/s de geração em CPU.
- [x] `AgenteV2/.venv` recriado, com Chromium.
- [x] AgenteV2 testado pelo terminal: pergunta simples e pesquisa na web.
- [x] `run-chat-web.ps1` grava a saída do servidor em `logs/`.
- [x] Exceções do Avast para `huggingface.co`, `us.aws.cdn.hf.co` e `pypi.org`.

## Falta fazer

- [ ] Decidir o contexto padrão (ver "Decisões em aberto").
- [ ] Rodar `janas-bench` com a GPU, comparando com a CPU.
- [ ] Testar a interface web do AgenteV2 e o servidor MCP pelo Cline (até aqui só foi verificado que carregam).
- [ ] Testar uma pesquisa que abra uma página dinâmica no Chromium.
- [ ] Testar o 35B pelo AgenteV2.
- [ ] Conferir se os acentos saem certos na interface web (no teste por PowerShell apareceu `Ã©`).
- [ ] Aumentar o arquivo de paginação, hoje fixo em 4,3 GB (depende do usuário: exige administrador e reinício).

## Decisões em aberto

- **Contexto padrão de `run-chat-web.ps1`:** hoje é 65536. O usuário subiu para 200000 depois da perda de arquivos, e esse valor foi reduzido depois. Para usar 200k no Cline, é preciso rodar com `-Context 200000` e mudar o Context Window do Cline para 200000. Não alterar sem perguntar.

## Decisões tomadas

- Servidor em janela própria do Windows Terminal, fora do VS Code: trocar de workspace encerra os terminais integrados e o servidor junto.
- Cada projeto mantém `spec.md` e `infra.md`, e o trabalho é feito em etapas (ver README).

## Histórico de incidentes

- **2026-10-31, ~20:00:** o modelo 80B, trabalhando como agente, perdeu o contexto e executou uma deleção geral no diretório errado. Foram perdidos os arquivos ignorados pelo git: modelos, venvs, downloads, `.token`, `.stats.json` e `results/`. Por isso as regras de segurança em [infra.md](infra.md) existem.
