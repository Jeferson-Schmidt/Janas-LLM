# Janas LLM Hardware Test Bench

Workspace independente para instalar e avaliar o projeto upstream [prabanta-dev/janas](https://github.com/prabanta-dev/janas) neste PC. 

## Hardware registrado

- AMD Ryzen 9 7900X, 12 núcleos / 24 threads
- 32 GB DDR5 (2 x 16 GB), atualmente a 4800 MHz por estabilidade. DDR5-6000 causou travamento; não reative EXPO/6000 sem uma decisão explícita.
- NVIDIA GeForce RTX 5070, 12 GB de VRAM, driver 616.92; Vulkan enumera a GPU em API 1.4.351
- NVMe de 4 TB em `D:`; cerca de 599 GB livres no momento da coleta
- Windows 11 Pro, build 26200

## Estrutura

- `bin/`: pacote oficial do Janas para Windows
- `downloads/`: arquivo ZIP de release
- `models/`: modelos; mantidos no NVMe D:
- `results/`: relatórios do `janas-bench`
- `scripts/`: instalação, diagnóstico e benchmark

Os diretórios de modelos e resultados são criados/ignorados localmente; pesos e relatórios não devem ser adicionados ao controle de versão.

## Preparação

Abra este diretório como workspace no VS Code e, em PowerShell:

```powershell
.\scripts\install-janas.ps1
.\scripts\check-hardware.ps1
```

O instalador baixa o ZIP oficial mais recente do projeto para `downloads/` e o extrai em `bin/`. Ele não baixa modelos. O diagnóstico é somente leitura e exibe `vulkaninfo --summary` quando disponível.

## Benchmark

O benchmark padrão é o Qwen3-4B Q4_K_M, uma primeira verificação menor (cerca de 2,5 GB para baixar):

```powershell
.\scripts\run-benchmark.ps1
```

O script configura `JANAS_MODELS` para `D:\Janas LLM\models` e grava o relatório em `results/`. Se o modelo não estiver instalado, o Janas poderá pedir confirmação para baixá-lo. O benchmark testa as configurações disponíveis e ajusta o perfil da máquina; deixe o PC ocioso e feche overlays antes de medir.

O script passa `--reserve 8`, deixando 8 GiB fora do orçamento do cache de especialistas para o Windows e os demais programas. Essa reserva dimensiona o cache do Janas; não é um limite rígido de memória imposto pelo Windows. Evite executar outros programas pesados durante os testes.

Para abrir o chat com a mesma reserva:

```powershell
.\scripts\run-chat.ps1
```

Para o smoke test inicial sem usar a RTX:

```powershell
.\scripts\run-chat.ps1 -CpuOnly
```

Se o TUI mostrar símbolos corrompidos ou linhas rolando no terminal integrado do VS Code, abra o chat em uma janela dedicada do Windows Terminal:

```powershell
wt.exe -w new -d "D:\Janas LLM" cmd.exe /k "D:\Janas LLM\scripts\run-chat-window.cmd"
```

Esse lançador usa UTF-8 apenas na nova janela e inicia o Qwen3.6-35B-A3B em CPU-only, com a reserva de 8 GiB.

Para baixar o Qwen3-Next-80B-A3B convertido (cerca de 49,4 GB) para o NVMe, execute em PowerShell na pasta `D:\Janas LLM`:

```powershell
.\bin\janas\janas-get.exe qwen3-next-80b-a3b --dir .\models
```

O download é verificado por SHA-256. Depois, para usar a página web com contexto reduzido a 8.192 tokens, por padrão em CPU-only:

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b -Context 8192
```

Para selecionar a RTX 5070, passe o switch `-Gpu` (equivalente a `-Gpu:$true`); `-Gpu:$false` força CPU-only:

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b -Context 8192 -Gpu
```

O modelo 80B continua maior que a VRAM e roda por streaming, com os especialistas quentes na RAM e operações selecionadas na GPU. A GPU discreta só recebe trabalho se o Janas considerar útil; a velocidade do 80B com a RTX 5070 ainda não foi medida. O script não baixa modelos por conta própria.

O chat pula a calibração automática por padrão para começar diretamente; passe `-Tune` para solicitar essa medição explicitamente.

Use esses wrappers para iniciar benchmark ou chat: executar os binários diretamente não aplica a reserva de 8 GiB.

Se o TUI do terminal integrado repetir linhas ou exibir caracteres corrompidos, use a página de chat local em vez do desenho de terminal:

```powershell
.\scripts\run-chat-web.ps1
```

Abra `http://127.0.0.1:8080/test`. O servidor escuta apenas neste PC, reserva 8 GiB, não salva conversas (`--no-store`) e não inicia ferramentas MCP. Sem `-Gpu` usa CPU-only; com `-Gpu` seleciona a GPU discreta. Em `Settings`, selecione `off` em `Reasoning` para respostas diretas. Para encerrar, pressione Ctrl+C no terminal onde o servidor está rodando.

Para uma comparação explicitamente sem GPU:

```powershell
.\scripts\run-benchmark.ps1 -CpuOnly
```

Depois, modelos maiores podem ser selecionados, um por execução:

```powershell
.\scripts\run-benchmark.ps1 -Model qwen3.6-35b-a3b
.\scripts\run-benchmark.ps1 -Model qwen3-next-80b-a3b
.\scripts\run-benchmark.ps1 -Model qwen3-30b-a3b
```

Recomendo começar pelo 4B para validar a execução, depois testar o 30B e o 35B. O 80B é um teste de capacidade/streaming pelo NVMe, não uma promessa de maior velocidade. O Janas é experimental; acompanhe o sistema e não comece por uma sessão longa com o PC ocupado.

## GPU e limitações

O Janas usa Vulkan, não CUDA, e escolhe por medição quais etapas delegar à GPU. Vulkan reconhecer a RTX 5070 não garante que todos os requisitos específicos do Janas passem. Após instalar, execute o `vkcheck` incluído no pacote, se presente. O suporte desta RTX 5070 não foi validado diretamente nos benchmarks publicados pelo repositório; confirme com o `vkcheck` e `janas-bench` locais.

A primeira etapa é nativa no Windows, sem Docker: reduz variáveis e preserva o caminho direto ao NVMe e ao driver Vulkan. O `vkcheck` passou com o driver NVIDIA 616.92. O primeiro `janas-bench` com GPU terminou sem produzir métricas finais; não use esse relatório como resultado de desempenho. A comparação CPU-only ainda não foi executada.

Para abrir um tunel cloudflared para acesso externo, copie o cloudflared.exe para o diretório raiz do projeto
digite no terminal, dentro do diretório raiz .\cloudflared.exe tunnel --url http://127.0.0.1:8080
Mantenha a janela de terminal com o tunel aberta para manter o acesso externo
