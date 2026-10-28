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

O download é verificado por SHA-256. Depois, para usar a página web com o 80B (por padrão em CPU-only):

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q
```

No `run-chat-web.ps1` o nome do 80B termina em `-q` de propósito: ele seleciona o arquivo do modelo (`qwen3-next-80b-a3b-q4km.jns`) e não o bloco de predição MTP que fica ao lado (`qwen3-next-80b-a3b-mtp-q4k.jns`). O janas-server carrega esse bloco sozinho, o que acelera a geração.

**Os dois modelos grandes foram testados e funcionam neste PC: Qwen3.6-35B-A3B e Qwen3-Next-80B-A3B.** O contexto padrão do `run-chat-web.ps1` é 65.536 tokens; use `-Context 8192` (ou 4096/16384) para reduzi-lo.

Para permitir que o Janas use a RTX 5070, passe o switch `-Gpu` (equivalente a `-Gpu:$true`); `-Gpu:$false` força CPU-only:

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q -Gpu
```

### Cache de especialistas (`-Cache`)

Por padrão, o janas-server escolhe sozinho o tamanho do cache de especialistas, a parte do modelo mantida na RAM, pela memória livre **no momento em que inicia**, deixando 8 GiB (`--reserve 8`) para os outros programas. Com o VS Code, o navegador e o Chromium abertos, ele pode escolher pouco: já foi visto "expert cache 1.0 GiB" no 80B, e então quase todo especialista é lido do SSD a cada token. O tamanho escolhido aparece na descrição do modelo, no início do servidor.

Para fixar o tamanho:

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q -Cache 10
.\scripts\run-chat-web.ps1 -Cache 12 -DryRun   # só mostra os limites e o comando, sem iniciar
```

Com `-Cache`, o Janas **não aplica o `--reserve`**, então o script valida o valor antes de iniciar e recusa, com mensagem, o que não couber no menor de dois limites:

- **Teto fixo: 50% da RAM** (15,5 GiB numa máquina de 32 GB). O autor do Janas mede o 80B com 12-16 GiB de cache em 32 GB. Acima disso o ganho é pequeno, porque os especialistas mais usados já cabem, e sobra menos RAM para o cache de arquivos do Windows, que também acelera a leitura do SSD.
- **Limite do momento: RAM disponível agora menos 6 GiB.** A margem cobre o que o servidor usa além do cache (~4 GiB: pesos fora dos especialistas, estado do contexto, conversas mantidas) e uma folga para os programas abertos crescerem (~2 GiB).

Exemplo: com 16,7 GiB disponíveis, o máximo é 10,6 GiB. Para poder usar mais, feche programas pesados antes de iniciar. Os dois limites (`$CacheMaxFractionOfRam`, `$CacheSafetyMarginGiB`) ficam no início de [scripts/run-chat-web.ps1](scripts/run-chat-web.ps1). Sem `-Cache` (ou com `-Cache 0`), tudo funciona como antes. Valores decimais são aceitos (`-Cache 10.5`, com ponto).

Os limites tornam um travamento muito improvável, mas não impossível: se outro programa crescer muito depois que o servidor iniciou, o Windows passa a usar o arquivo de paginação e tudo fica lento. Nesse caso, reinicie o janas-server com um `-Cache` menor.

O modelo roda na CPU, na RAM e no SSD: os pesos ficam no NVMe e os especialistas mais usados ficam em cache na RAM. A GPU não carrega o modelo; com `-Gpu` o Janas só a usa nas etapas em que mede ganho, principalmente na leitura do prompt (o "fast prompt", que manda blocos do prompt para a GPU). A geração de cada token continua na CPU. O script não baixa modelos por conta própria.

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

O 35B e o 80B já foram validados no chat; o benchmark mede a velocidade de cada um. O 80B lê os especialistas pelo NVMe, então é maior, mas não necessariamente mais lento por token. O Janas é experimental; acompanhe o sistema e não comece por uma sessão longa com o PC ocupado.

## GPU e limitações

O Janas executa o modelo na CPU, com os pesos no SSD e o cache de especialistas na RAM. A GPU é opcional: ele usa Vulkan, não CUDA, e escolhe por medição quais etapas delegar a ela (sobretudo a leitura de prompts). Segundo a documentação do próprio Janas (`bin/janas/docs/hardware.md`), o "fast prompt" ainda não havia sido confirmado em GPUs discretas; se as respostas saírem estranhas com `-Gpu`, `JANAS_GPU_FAST_PROMPT=0` desliga esse caminho. Vulkan reconhecer a RTX 5070 não garante que todos os requisitos específicos do Janas passem. Após instalar, execute o `vkcheck` incluído no pacote, se presente. O suporte desta RTX 5070 não foi validado diretamente nos benchmarks publicados pelo repositório; confirme com o `vkcheck` e `janas-bench` locais.

A primeira etapa é nativa no Windows, sem Docker: reduz variáveis e preserva o caminho direto ao NVMe e ao driver Vulkan. O `vkcheck` passou com o driver NVIDIA 616.92. O primeiro `janas-bench` com GPU terminou sem produzir métricas finais; não use esse relatório como resultado de desempenho. A comparação CPU-only ainda não foi executada.

## Agente com pesquisa na internet (AgenteV2)

`AgenteV2/` é um agente que conversa com o janas-server e pesquisa na internet quando precisa de informação atual: busca, lê 3 páginas (estáticas e dinâmicas, via Chromium), resume no próprio modelo e responde com as fontes. Tem interface web com o uso de tokens sobre o contexto e acesso externo protegido por token. Instruções em [AgenteV2/README.md](AgenteV2/README.md).

Também funciona no VS Code, com o Cline e o modelo local, sem custo: o agente vira um servidor MCP que dá ao Cline as ferramentas de pesquisa e de abrir links (veja "No VS Code, com o Cline" no README do agente).

A versão anterior continua em `Agente/` (e na tag git `agente-v1`).

## Acesso externo (cloudflared)

Copie o `cloudflared.exe` para a raiz do projeto e aponte o túnel para o **agente** (porta 8090), que exige token:

```powershell
.\cloudflared.exe tunnel --url http://127.0.0.1:8090
```

Mantenha a janela do túnel aberta enquanto quiser o acesso externo.

**Não aponte o túnel para a porta 8080.** O janas-server não pede senha: qualquer pessoa com o endereço `trycloudflare.com` usaria o modelo e a API inteira. Se precisar mesmo expor o servidor, inicie-o com `--api-key`.
