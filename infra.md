# Infra: Janas LLM

Planejamento de infraestrutura deste projeto. Leia antes de instalar, mover, apagar ou reconfigurar qualquer coisa. O andamento do trabalho está em [spec.md](spec.md).

Última atualização: 2026-11-05

## Regras de segurança

- **Nunca rode deleção recursiva** (`rm -rf`, `Remove-Item -Recurse`, `rmdir /s`, `git clean`) sem confirmação do usuário.
- Antes de qualquer deleção, confirme o diretório atual e liste o que será apagado.
- Se não souber em que pasta ou etapa está, pare e releia este arquivo e o `spec.md`.
- Não mexa em `models/`: são cerca de 72 GB, e baixar de novo leva horas.

## Máquina

| Item | Valor |
|---|---|
| CPU | AMD Ryzen 9 7900X, 12 núcleos / 24 threads |
| RAM | 32 GB DDR5 a 4800 MHz. Não reativar EXPO/6000: causou travamento |
| GPU | NVIDIA RTX 5070, 12 GB de VRAM. O Janas usa Vulkan, não CUDA |
| Disco | NVMe de 4 TB em `D:` |
| Sistema | Windows 11 Pro |
| Arquivo de paginação | Fixo em 4,3 GB, limite de commit de ~35 GB. Com o servidor rodando, sobram de 1 a 4 GB de commit |

## Serviços

| Serviço | Endereço | Como iniciar |
|---|---|---|
| janas-server | `http://127.0.0.1:8080` (API em `/v1`, chat em `/test`) | `.\scripts\run-chat-web.ps1` |
| AgenteV2 web | `http://127.0.0.1:8090` | `.\AgenteV2\run-agent-web.ps1` |
| AgenteV2 terminal | sem porta | `.\AgenteV2\run-agent.ps1` |
| Servidor MCP | iniciado pelo Cline | `AgenteV2\mcp_server.py` |
| Acesso externo | túnel para a porta 8090 | `cloudflared tunnel --url http://127.0.0.1:8090` |

O janas-server precisa estar rodando antes dos outros. Inicie-o em uma janela própria do Windows Terminal, porque trocar de workspace no VS Code encerra os terminais integrados:

```powershell
wt.exe -w new -d "D:\Janas LLM" powershell.exe -NoExit -ExecutionPolicy Bypass -File "D:\Janas LLM\scripts\run-chat-web.ps1" -Model qwen3-next-80b-a3b-q
```

## Modelos

Ficam em `D:\Janas LLM\models`, o mesmo valor de `JANAS_MODELS`.

| Arquivo | Tamanho | Uso |
|---|---|---|
| `qwen3-next-80b-a3b-q4km.jns` | 48,4 GB | Modelo 80B (`-Model qwen3-next-80b-a3b-q`) |
| `qwen3-next-80b-a3b-mtp-q4k.jns` | 0,9 GB | Bloco MTP do 80B, carregado sozinho pelo servidor |
| `qwen3.6-35b-a3b-q4km.jns` | 22,3 GB | Modelo 35B, padrão do script, MTP embutido |

## Memória

- O KV cache do contexto inteiro é alocado na partida. No modo automático, um contexto maior tira memória do cache de especialistas.
- KV do 80B, em estimativa: ~0,8 GB em 65k e ~2,5 GB em 200k.
- `--reserve 8` deixa 8 GiB para os outros programas. Com `-Cache`, quem valida o limite é o script.

## Contexto

- `run-chat-web.ps1`: padrão 65536; aceita 4096, 8192, 16384, 65536 e 200000.
- AgenteV2: limite de 65535 (`CONTEXT_WINDOW` em `AgenteV2/config.py`).
- Cline: o campo Context Window precisa ter o mesmo valor do `-Context` do servidor.

## O que está no git e o que se recupera

| Item | No git | Como recuperar |
|---|---|---|
| Código, scripts, documentação | Sim | `git` |
| `bin/`, `downloads/` | Não | `.\scripts\install-janas.ps1 -Force` |
| `models/` | Não | `janas-get <modelo> --dir .\models` (horas) |
| `AgenteV2/.venv` | Não | Apagar a pasta e rodar `.\AgenteV2\setup-agent.ps1` |
| `AgenteV2/.token` | Não | Recriado sozinho, mas o token muda e links salvos deixam de valer |
| `AgenteV2/.stats.json` | Não | **Não se recupera** |
| `logs/`, `results/*.txt` | Não | **Não se recupera** |

## Rede

- O Avast inspeciona HTTPS. O `janas-get` e o pip falham quando um site não está nas exceções.
- Exceções em uso: `https://huggingface.co/*`, `https://us.aws.cdn.hf.co/*` e `https://pypi.org/*`.
- Se um download der erro de certificado, veja primeiro se o host é novo. Não desligue a verificação TLS.
