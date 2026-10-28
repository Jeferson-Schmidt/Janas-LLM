# Agente Janas v2

Agente que conversa com um modelo local rodando no [Janas](https://github.com/prabanta-dev/janas) (janas-server) e pesquisa na internet quando a pergunta depende de informação atual. Ele busca, lê 3 páginas (estáticas ou montadas por JavaScript), resume e responde citando as fontes.

Tem interface web com o uso de tokens sobre o contexto e acesso externo protegido por token.

A versão anterior, só de terminal, continua em `../Agente/` e na tag git `agente-v1`.

## Pré-requisitos

- **Windows 10/11 com PowerShell.** Os scripts são `.ps1`; o código Python em si é portável.
- **Python 3.10 ou mais novo** no PATH, como `py` ou `python` ([python.org](https://www.python.org/downloads/)).
- **Janas instalado e um modelo baixado**, conforme o [README principal](../README.md):

  ```powershell
  .\scripts\install-janas.ps1
  .\bin\janas\janas-get.exe qwen3.6-35b-a3b --dir .\models
  ```

  Testados com o agente: **Qwen3.6-35B-A3B** e **Qwen3-Next-80B-A3B**. O modelo precisa suportar chamadas de ferramenta (tools). Os Qwen3, Qwen3.5, Qwen3.6 e Qwen3-Next suportam.
- Cerca de **500 MB de disco** para o ambiente do agente (dependências + Chromium).
- Internet, para a busca e as páginas. O modelo em si continua rodando só no seu PC.

### Permissão para rodar scripts

Se o PowerShell disser que "a execução de scripts foi desabilitada neste sistema", libere os scripts locais para o seu usuário (uma vez só):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Ou rode um script específico sem mudar nada: `powershell -ExecutionPolicy Bypass -File .\setup-agent.ps1`.

## Instalação (uma vez)

Na pasta do repositório:

```powershell
cd AgenteV2
.\setup-agent.ps1
```

O script:

- cria um ambiente virtual isolado em `AgenteV2\.venv\`;
- instala nele as dependências de [requirements.txt](requirements.txt) e o Chromium do Playwright (~150 MB, em `.venv\browsers\`).

O Python do sistema não é alterado, e apagar a pasta `.venv` remove tudo. Para atualizar as dependências, rode o script de novo.

## Como rodar (três terminais)

```
[Terminal 1] janas-server   127.0.0.1:8080   o modelo (só neste PC, sem senha)
[Terminal 2] agente v2      127.0.0.1:8090   interface web, com token
[Terminal 3] cloudflared    túnel para a 8090 (opcional, acesso pela internet)
```

**Terminal 1**: o janas-server, a partir da raiz do repositório:

```powershell
.\scripts\run-chat-web.ps1 -Model qwen3.6-35b-a3b
# ou o 80B: .\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q
# -Gpu deixa o Janas usar a GPU onde ele medir ganho (principalmente na leitura de prompts)
```

Espere o servidor terminar de carregar. O primeiro pedido depois de iniciar é mais lento, porque o cache de especialistas ainda está enchendo.

**Terminal 2**: o agente:

```powershell
cd AgenteV2
.\run-agent-web.ps1
```

O terminal mostra o endereço, o token de acesso e um link pronto. Abra `http://127.0.0.1:8090/?token=SEU_TOKEN` no navegador.

Para usar no terminal em vez do navegador: `.\run-agent.ps1`. Os comandos são `sair`, `limpar` (nova conversa) e `pensar` (liga/desliga o raciocínio).

O agente descobre sozinho qual modelo o servidor carregou (`GET /v1/models`). Para trocar de modelo, reinicie só o Terminal 1. Se o servidor cair, a interface mostra "janas-server offline" e volta a funcionar quando ele subir de novo.

Parâmetros de `run-agent-web.ps1`:

| Parâmetro | Padrão | Uso |
|---|---|---|
| `-Port` | 8090 | porta da interface web |
| `-BaseUrl` | `http://127.0.0.1:8080/v1` | endereço do janas-server; troque se ele roda em outra porta ou em outro PC |
| `-Lan` | desligado | escuta em `0.0.0.0` para acesso direto pela rede local (não é preciso para o cloudflared) |

O `run-agent.ps1` aceita `-BaseUrl`.

**Terminal 3** (opcional): acesso pela internet com o [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/). Baixe o `cloudflared.exe`, coloque-o na raiz do repositório (ele está no `.gitignore`) e rode:

```powershell
.\cloudflared.exe tunnel --url http://127.0.0.1:8090
```

Ele mostra um endereço `https://xxxx.trycloudflare.com`. Abra `https://xxxx.trycloudflare.com/?token=SEU_TOKEN` no celular ou em outro PC. O endereço muda toda vez que o túnel é reiniciado, e o acesso dura enquanto essa janela estiver aberta.

> **Não aponte o túnel para a porta 8080.** O janas-server não pede senha: qualquer pessoa com o endereço usaria o modelo e a API inteira. O agente (8090) é que tem o token.

## No VS Code, com o Cline (sem custo)

O [Cline](https://github.com/cline/cline) é uma extensão gratuita e de código aberto que programa dentro do VS Code: lê e edita arquivos mostrando o diff, roda comandos no terminal e pede sua aprovação antes de cada ação. Com ele apontado para o janas-server, **o modelo é o seu, local, e não há custo**. O agente v2 entra como **servidor MCP** ([mcp_server.py](mcp_server.py)), que dá ao Cline as ferramentas `web_research` (pesquisa com 3 páginas e resumo) e `fetch_url` (abrir um link). São o mesmo código e as mesmas proteções da interface web.

### Como as peças se ligam (e por que a Base URL é a 8080)

```
            ┌── Base URL (porta 8080) ───→ janas-server   ← o modelo, que pensa e escreve o código
Cline ──────┤
            └── MCP (stdio, sem porta) ──→ mcp_server.py  ← as ferramentas de internet
                                              ├→ internet (busca, páginas, Chromium)
                                              └→ janas-server :8080 (resumo das páginas)

Navegador ──→ :8090 interface web do agente ──→ janas-server :8080   (independente do Cline)
```

- **A Base URL do Cline é a 8080** (janas-server), não a 8090. O Cline precisa de uma API de modelo no padrão da OpenAI, e é isso que o janas-server oferece. A 8090 é a interface web do agente para pessoas: tem rotas próprias, pede token e já tem o próprio laço de ferramentas.
- **O servidor MCP não usa porta.** O Cline inicia o `mcp_server.py` como processo filho e conversa com ele pela entrada e saída padrão (stdio). Por isso o `run-agent-web.ps1` não é necessário para o Cline; ele pode ficar rodando ao mesmo tempo, para uso pelo navegador.
- **Para usar o Cline, só o janas-server precisa estar no ar** (Terminal 1).

### Passo a passo

**1. Instale o Cline:** no VS Code, aba Extensões (`Ctrl+Shift+X`), procure **Cline** (autor: saoudrizwan). Ou, no terminal:

```powershell
code --install-extension saoudrizwan.claude-dev
```

**2. Gere a configuração** com os caminhos da sua máquina. O script só mostra; não altera nada:

```powershell
cd AgenteV2
.\configurar-cline.ps1
```

**3. Na tela de boas-vindas ("How will you use Cline?"), escolha "Bring my own API key"** ("Use Cline with your provider of choice") e clique em *Continue*.

As outras opções usam modelos **na nuvem**, com login e, em alguns casos, cobrança:
- **"Absolutely Free":** modelos gratuitos na nuvem. O seu código sai do PC.
- **"ClinePass":** assinatura paga.
- **"Frontier Model":** Claude, GPT e outros modelos pagos.

Se já passou dessa tela, a mesma configuração fica na engrenagem do Cline → *API Configuration*.

**4. Configure o provedor e o modelo:**

| Campo | Valor | Observação |
|---|---|---|
| API Provider | **OpenAI Compatible** | não use "Ollama" nem "LM Studio", que são outros servidores |
| Base URL | `http://127.0.0.1:8080/v1` | o janas-server |
| API Key | `local` | qualquer texto; só importa se o janas-server foi iniciado com `--api-key` |
| Model ID | `janas` | qualquer nome: o servidor usa o modelo que carregou |
| Custom Headers | nenhum | se clicar em "Add header" sem querer, remova a linha (ícone de lixeira) ou deixe os campos vazios |

Em **Model Configuration**:

| Campo | Valor | Por quê |
|---|---|---|
| Context Window | `65536` | o mesmo `-Context` do `run-chat-web.ps1` |
| Max Output Tokens | `8192` | o Cline às vezes reescreve arquivos inteiros; um limite baixo corta a edição no meio |
| Temperature | `0.3` | edições e chamadas de ferramenta mais consistentes. Se o modelo entrar em repetição (a mesma linha em loop), suba para 0.5-0.7; a Qwen recomenda 0.7 para conversa e desaconselha 0 |
| Supports Images | **desmarcado** | o janas-server só aceita texto e responde 400 a imagens (*"only text parts are supported"*). O Qwen3-Next-80B-A3B-Instruct também é só de texto |
| Input / Output Price | `0` | o modelo é local; assim o contador de custo do Cline mostra US$ 0,00 |
| Reasoning / thinking | desligado, se aparecer | os modelos *Instruct* não têm modo de raciocínio |

Para conferir: mande "oi" no Cline. A resposta tem que aparecer no terminal do janas-server como uma requisição.

**5. Registre o servidor MCP:** no Cline, ícone *MCP Servers* → aba *Installed* → **Configure MCP Servers**. Isso abre o `cline_mcp_settings.json`. Cole o bloco `janas-pesquisa` que o script mostrou (se já houver outros servidores, acrescente só esse bloco dentro de `"mcpServers"`) e salve. O servidor deve aparecer com ponto verde e as duas ferramentas.

Exemplo do que o script gera (os caminhos serão os da sua máquina):

```json
{
  "mcpServers": {
    "janas-pesquisa": {
      "command": "D:\\Janas LLM\\AgenteV2\\.venv\\Scripts\\python.exe",
      "args": ["D:\\Janas LLM\\AgenteV2\\mcp_server.py"],
      "env": {
        "JANAS_BASE_URL": "http://127.0.0.1:8080/v1",
        "JANAS_MCP_SUMMARIZE": "on"
      },
      "disabled": false,
      "timeout": 300,
      "autoApprove": []
    }
  }
}
```

- `command`: o Python do venv do agente. Use esse, e não o do sistema, porque é ele que tem as dependências e o Chromium.
- `timeout: 300`: uma pesquisa leva 1-2 minutos em CPU, e o padrão do Cline (60 s) cortaria antes.
- `autoApprove`: vazio = o Cline pede aprovação a cada chamada. Como as duas ferramentas só leem a internet (são marcadas como somente leitura), você pode liberá-las: `"autoApprove": ["web_research", "fetch_url"]`, ou marque *Auto-approve* na lista de ferramentas do servidor. Edições de arquivo e comandos continuam pedindo aprovação, conforme as opções do próprio Cline.

**6. Use**, com o janas-server rodando:

- "Pesquise qual é a versão mais recente do FastAPI e atualize o requirements.txt"
- "Leia https://github.com/dono/repo/blob/main/README.md e crie um script de instalação para Windows"

### O servidor MCP ([mcp_server.py](mcp_server.py))

| Ferramenta | Parâmetros | O que faz |
|---|---|---|
| `web_research` | `query` (consulta de busca), `pergunta` (opcional: a pergunta do usuário, usada para escolher e resumir o que importa) | busca, lê as 3 páginas mais relevantes (estáticas ou com JavaScript, pelo Chromium), filtra os trechos e devolve um resumo com as fontes. Leva 1-2 minutos em CPU. |
| `medir_velocidade` | `prompt`, `execucoes` (1-5, padrão 3), `max_tokens` (32-512, padrão 256), `ampliar_leitura` (padrão desligado) | mede a velocidade do modelo carregado: **mínimo e máximo** de leitura (prompt) e de escrita (geração, em janelas de 1 s), mais o tempo até o 1º token. Envia o `prompt` ao janas-server `execucoes` vezes, cada uma com um identificador único para não medir o cache. Mostra também a configuração do servidor (cache de especialistas, GPU). Só é usada quando você pede explicitamente, por exemplo: "teste a velocidade em tokens por segundo usando este prompt, máximo e mínimo de leitura e escrita". Leva 1-2 minutos. |
| `fetch_url` | `url`, `pergunta` (opcional) | abre exatamente aquele endereço. Links de arquivo do GitHub viram o arquivo cru; páginas grandes são reduzidas aos trechos mais relevantes (`FETCH_URL_MAX_CHARS`). Leva menos de 1 s para baixar. |

Variáveis de ambiente (no `"env"` da configuração):

| Variável | Padrão | Uso |
|---|---|---|
| `JANAS_BASE_URL` | `http://127.0.0.1:8080/v1` | janas-server usado para os resumos |
| `JANAS_MCP_SUMMARIZE` | `on` | `on`: resume as 3 páginas no janas-server e devolve só o resumo (ocupa pouco contexto do Cline). `off`: devolve o texto filtrado, sem a chamada de resumo; ~1 minuto mais rápido por pesquisa, mas ocupando bem mais contexto. `.\configurar-cline.ps1 -NoSummarize` gera a configuração com `off`. |

Sobre o `medir_velocidade`:

- **Ele não mede a resposta do Cline enquanto ela é gerada.** Quando o modelo chama uma ferramenta, a geração dele para até a ferramenta terminar. Por isso a medição é controlada: a ferramenta envia o seu prompt ao modelo e cronometra.
- **Prompt curto mede mal a leitura.** Com menos de 200 tokens, o custo fixo de cada chamada domina e a taxa sai abaixo da real (num teste: ~23 tok/s com o prompt de ~100 tokens, contra 55,7 tok/s com `ampliar_leitura`). Peça "com leitura ampliada" para repetir o texto até ~1.024 tokens, como o `janas-bench` faz.
- **Escrita com mínimo 0:** houve pelo menos 1 s sem tokens, uma pausa real na geração. É comum logo depois de reiniciar o servidor, enquanto o cache de especialistas ainda enche ("experts loading in the background" na configuração). A ferramenta avisa nos dois casos.
- **Não ponha no `autoApprove`:** cada medição ocupa o modelo por 1-2 minutos e pode tirar a conversa do Cline do cache do servidor (cada execução é uma conversa nova, e o `--keep 8` guarda só 8).
- **Ótima para comparar valores de `-Cache`:** a configuração do servidor aparece no topo do resultado. Para medidas de referência, continue usando o `janas-bench`.

Outros comportamentos:

- **Mesmas regras do agente:** bloqueio de endereços internos, cache de 1 h, conteúdo de sites marcado como dado e não como instrução. Os valores de [config.py](config.py) (páginas por pesquisa, tamanhos, timeouts) valem aqui também.
- **Andamento:** cada etapa ("Buscando...", "[1] python.org...") é enviada ao Cline como notificação de progresso.
- **Estatísticas:** os resumos feitos pelo Cline entram no painel "Desempenho por modelo" da interface web (mesmo `.stats.json`).
- **Mudanças no código** só valem depois de reiniciar o servidor no Cline: na lista de servidores MCP, botão de reiniciar (*Restart*), ou desligue e ligue o servidor.
- **Teste sem o Cline:** `.\.venv\Scripts\python.exe mcp_server.py` deve ficar parado, esperando mensagens na entrada. É o comportamento certo de um servidor stdio; encerre com Ctrl+C.
- **Outros clientes:** o mesmo servidor funciona no Continue, no Roo Code e no Claude Code, com o mesmo `command` e `args`.

### O que esperar de desempenho

- **A primeira mensagem de cada tarefa é lenta.** O Cline manda um prompt de sistema grande (instruções, ferramentas e o estado do projeto), de vários milhares de tokens. Com a leitura a ~50 tok/s medida neste PC, só lê-lo pode levar alguns minutos.
- **As mensagens seguintes são bem mais rápidas.** O janas-server guarda o início da conversa em cache (inclusive em disco, entre reinícios).
- **O contexto enche mais cedo.** Esse prompt ocupa parte dos 65 mil tokens, então tarefas longas enchem o contexto antes que no chat do agente.
- **Cache de especialistas pequeno deixa tudo lento.** O tamanho aparece na descrição do modelo, no início do janas-server (ex.: "expert cache 1.0 GiB"). Ele é calculado pela RAM livre na partida, então inicie o janas-server com poucos programas abertos, ou fixe o tamanho com `-Cache` (ex.: `.\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q -Cache 10`). O script valida o valor contra a memória disponível; veja "Cache de especialistas" no [README principal](../README.md). No Qwen3-Next-80B, o autor do Janas mede com 12-16 GiB de cache.

## Token de acesso

- **Onde fica no código:** a função `get_access_token()` em [config.py](config.py) decide o token, e o middleware `autenticacao` em [web_app.py](web_app.py) faz a verificação.
- **De onde vem**, em ordem:
  1. da variável de ambiente `JANAS_AGENT_TOKEN`, se estiver definida;
  2. senão, do arquivo `AgenteV2\.token`;
  3. senão, o agente gera um token aleatório na primeira execução e grava em `.token`.

  O `.token` está no `.gitignore` e nunca vai para o git.
- **Onde ver:** no Terminal 2, sempre que o agente inicia, ou no próprio arquivo `.token`.
- **Como entrar:**
  - abra o endereço com `?token=SEU_TOKEN` no final; ou
  - abra o endereço sem token e digite-o na tela de login.

  O navegador guarda um cookie por 30 dias (`HttpOnly`, e `Secure` quando o acesso é por https) e a URL fica limpa.
- **Trocar o token:** apague o `.token` e reinicie o agente; um novo é gerado, e os navegadores conectados precisam entrar de novo. Para um token fixo, escolhido por você: `$env:JANAS_AGENT_TOKEN = 'um-token-longo-e-aleatorio'` antes do `run-agent-web.ps1`.
- **Proteções:**
  - depois de 10 tentativas erradas, o IP fica bloqueado por 10 minutos (pelo túnel, o IP real vem do cabeçalho `CF-Connecting-IP`);
  - chamadas à API sem o cookie, ou sem `Authorization: Bearer SEU_TOKEN`, recebem 401.
- **Uma conversa por navegador:** cada navegador recebe o próprio cookie de sessão, então o celular e o PC têm históricos separados. As conversas ficam só na memória do agente e somem quando ele é reiniciado.

## A interface

- **Chat** com a resposta aparecendo enquanto é gerada.
  - Durante uma pesquisa, mostra cada etapa: busca, cada página lida (com o método `estática`, `dinâmica` ou `cache`) e o resumo.
  - Embaixo de cada resposta ficam as fontes, o tempo e os tokens do turno.
- **Parar:** interrompe a geração. A resposta parcial fica no histórico.
- **Raciocínio:** liga o "pensar antes de responder" do modelo. Melhora problemas difíceis, mas é bem mais lento.
- **Painel lateral** (botão "Tokens" no celular):
  - **Contexto da conversa:** tokens usados sobre o limite (65.535 por padrão), com a marca da compactação automática.
  - **Último turno e Sessão:** tokens lidos agora, reaproveitados do cache do servidor e gerados, além do tempo de leitura e de geração, separados entre a conversa e os resumos de páginas.
  - **Velocidade (tokens/s), em duas medidas separadas:**
    - **leitura** (prefill): quantos tokens de prompt o modelo lê por segundo. É o que manda no tempo das pesquisas e dos links;
    - **geração**: quantos tokens ele escreve por segundo. É o que define a fluidez da resposta.

    Durante a resposta, "Gerando agora" mostra uma estimativa ao vivo (com MTP, um pedaço do stream pode trazer mais de um token). No fim, o valor exato informado pelo servidor substitui a estimativa.
  - **Desempenho por modelo:** médias de leitura e geração de cada modelo, somando todas as conversas, separadas entre conversa e resumos. Serve para comparar o 35B com o 80B: troque o modelo no janas-server e as medições vão para a linha do modelo novo. Os dados ficam em `AgenteV2\.stats.json` (fora do git), sobrevivem a reinícios do agente e só são zerados pelo botão "Zerar estatísticas" (dois cliques).

  As médias são ponderadas (tokens totais ÷ tempo total). Chamadas pequenas ficam fora delas, porque nelas o custo fixo de cada chamada domina: leituras com menos de `RATE_MIN_READ_TOKENS` (200) e respostas com menos de `RATE_MIN_GEN_TOKENS` (16) tokens. Por isso uma pergunta curta, que lê quase tudo do cache, mostra a leitura como "—". As pesquisas e os links medem bem a leitura, porque leem milhares de tokens.
  - **Memória de pesquisa:** cada pesquisa com o resumo, as fontes e os tempos. Fica separada da conversa: o modelo recebe só o resumo.

Se você fechar a aba no meio de uma resposta, ela continua sendo gerada e aparece no histórico ao reabrir.

## Como uma pergunta é respondida

```
pergunta → modelo decide → web_research(consulta)
                               ├─ busca (DuckDuckGo via ddgs, ~2-4 s)
                               ├─ baixa ~8 resultados em paralelo (httpx + trafilatura)
                               ├─ página quase vazia? abre no Chromium (JavaScript)
                               ├─ escolhe as 3 páginas mais relevantes pelo conteúdo (BM25, sem LLM)
                               ├─ filtro BM25: só os trechos relevantes (~3.000 caracteres/página)
                               └─ UMA chamada de resumo para as 3 páginas, numa conversa à parte
                           ← só o resumo com as fontes volta para a conversa
           → modelo responde
```

**Links passados pelo usuário** ("resuma https://..."): o modelo usa a ferramenta `fetch_url`, que abre exatamente aquele endereço, sem busca:

- links de arquivo do GitHub (`github.com/.../blob/...`) são trocados pelo arquivo cru (`raw.githubusercontent.com`), que abre direto;
- texto, markdown, JSON, CSV e YAML entram como estão;
- páginas montadas por JavaScript vão para o Chromium;
- o texto entra direto na conversa, sem a chamada de resumo, marcado como conteúdo externo (o modelo é instruído a não seguir ordens escritas nele);
- acima de `FETCH_URL_MAX_CHARS` (16.000 caracteres, ~4 mil tokens), vão os trechos mais relevantes para a pergunta, completados com o resto do texto, na ordem, até o limite.

Endereços internos continuam bloqueados.

> **Links lentos?** Quase todo o tempo é o modelo lendo o texto do link, não o download (que leva menos de 1 s). Com o padrão de 16.000 caracteres, resumir um README grande levou ~134 s neste PC. Para respostas mais rápidas, reduza `FETCH_URL_MAX_CHARS` em [config.py](config.py): com `8000`, o tempo de leitura cai para mais ou menos a metade. A contrapartida é que, em páginas grandes, o modelo vê menos do texto.

Escolhas de desempenho:

- **A conversa só cresce no fim.** O Qwen3.6 e o Qwen3-Next têm estado recorrente: se uma mensagem antiga muda, o janas-server relê a conversa inteira. Por isso:
  - a data do prompt de sistema fica fixa na sessão;
  - a lista de ferramentas nunca muda (para proibir ferramentas o agente usa `tool_choice: none`);
  - a resposta parcial de um "Parar" também fica no histórico.

  Assim cada turno lê só o que é novo; o painel mostra isso em "reaproveitados (cache)".
- **Memória de pesquisa separada da memória de conversa.** O resultado completo de cada pesquisa fica no painel; a conversa recebe só o resumo curto. Pesquisas repetidas em até 1 h vêm do cache, sem baixar nem resumir de novo.
- **O resumo roda numa conversa separada** no mesmo servidor. O `--keep 8` padrão do janas-server mantém a conversa principal calculada enquanto isso.
- **Compactação automática:** ao passar de 85% do contexto, o agente pede ao modelo um resumo da conversa, acrescentando o pedido no fim (o servidor lê só ele). Depois a conversa recomeça a partir do resumo.

## Desempenho medido

Qwen3.6-35B-A3B num Ryzen 9 7900X com 32 GB de DDR5, NVMe e RTX 5070 (`-Gpu`). Seus números vão variar com o hardware.

| Situação | Tempo |
|---|---|
| Pergunta sem pesquisa (prompt de sistema já em cache) | 2-3 s |
| Primeira pergunta logo após iniciar o servidor | ~20 s |
| Pergunta com pesquisa de 3 páginas | ~110 s |
| ↳ modelo decide pesquisar | 8 s |
| ↳ busca + download das páginas | 6 s |
| ↳ resumo: ler ~2.600 tokens das páginas | 54 s |
| ↳ resumo: escrever ~150 tokens | 23 s |
| ↳ resposta final (983 tokens do cache, 289 novos) | 18 s |
| Resumir um link passado pelo usuário (`fetch_url`, README de 31 mil caracteres) | ~134 s |
| ↳ download do arquivo | 0,1 s |
| ↳ ler ~5.500 tokens (texto do link + conversa) | 96 s |
| ↳ escrever a resposta (~320 tokens) | 38 s |
| Compactação automática (uma vez, quando o contexto enche) | ~40 s |
| Geração do Qwen3-Next-80B-A3B (resposta de ~280 tokens) | 12,7 tok/s |

Em CPU, ler o prompt (~50 tokens/s neste PC) e gerar texto (~7-10 tokens/s) custam muito mais que a internet. Por isso o agente filtra as páginas sem LLM antes de mandá-las ao modelo.

### Resumo ou modo direto?

O resumo das páginas economiza **contexto**, mas não **tempo**: o modelo precisa ler as páginas e ainda escrever o resumo, e escrever é a etapa mais lenta. Há duas opções em [config.py](config.py):

- `SUMMARIZE_PAGES = True` (padrão): cada pesquisa ocupa ~400 tokens da conversa. Cabem dezenas de pesquisas antes de compactar.
- `SUMMARIZE_PAGES = False` (modo direto): os trechos filtrados entram direto na conversa, sem a chamada de resumo. A estimativa, feita a partir dos tempos medidos acima, é economizar ~30-40 s por pesquisa, mas cada pesquisa ocupa ~2.500 tokens.

Se a prioridade é velocidade, experimente o modo direto. Também ajudam: reduzir `CHARS_PER_PAGE` (menos texto lido por página) ou `PAGES_PER_SEARCH`. Para links passados pelo usuário, reduzir `FETCH_URL_MAX_CHARS` (por exemplo, de 16000 para 8000).

## Configuração ([config.py](config.py))

| Valor | Padrão | O que faz |
|---|---|---|
| `CONTEXT_WINDOW` | 65535 | contexto considerado na barra e na compactação. Se o servidor tiver `--ctx` menor, vale o menor. |
| `COMPACT_AT` | 0.85 | fração do contexto que dispara a compactação |
| `PAGES_PER_SEARCH` | 3 | páginas lidas e resumidas por pesquisa |
| `SEARCH_RESULTS` | 8 | resultados pedidos à busca (sobram para quando uma página falha) |
| `SEARCH_REGION` | `br-pt` | região da busca |
| `CHARS_PER_PAGE` | 3000 | caracteres por página enviados ao modelo depois do filtro (~800 tokens) |
| `SUMMARIZE_PAGES` | True | `False` = modo direto (acima) |
| `SUMMARY_MAX_TOKENS` | 350 | tamanho máximo do resumo de uma pesquisa |
| `FETCH_URL_MAX_CHARS` | 16000 | máximo de texto de um link passado pelo usuário (`fetch_url`) que entra na conversa; cada 4 mil tokens levam ~80 s para o modelo ler em CPU |
| `DYNAMIC_MIN_CHARS` | 800 | abaixo disso, a página é aberta no Chromium |
| `DYNAMIC_ENABLED` | True | `False` desliga o Chromium (só páginas estáticas) |
| `ANSWER_MAX_TOKENS` | 1500 | tamanho máximo de uma resposta |
| `TEMPERATURE` | 0.3 | temperatura das respostas |
| `CACHE_TTL_SECONDS` | 3600 | validade do cache de páginas e pesquisas |
| `MAX_SESSIONS` | 8 | conversas simultâneas (uma por navegador) |
| `RATE_MIN_READ_TOKENS` | 200 | leituras menores ficam fora da média de velocidade de leitura |
| `RATE_MIN_GEN_TOKENS` | 16 | respostas menores ficam fora da média de velocidade de geração |
| `STATS_FILE` | `.stats.json` | onde fica o desempenho acumulado por modelo |

Variáveis de ambiente, para não editar código:

| Variável | Padrão | Uso |
|---|---|---|
| `JANAS_BASE_URL` | `http://127.0.0.1:8080/v1` | endereço do janas-server (os scripts definem a partir de `-BaseUrl`) |
| `JANAS_API_KEY` | `not-needed` | se o janas-server foi iniciado com `--api-key` |
| `JANAS_MODEL` | vazio | força um modelo; vazio = o que o servidor carregou |
| `JANAS_CONTEXT_WINDOW` | 65535 | o mesmo que `CONTEXT_WINDOW` |
| `JANAS_THINK` | `off` | raciocínio ligado (`on`) por padrão |
| `JANAS_AGENT_TOKEN` | vazio | token de acesso fixo (senão usa `.token`) |
| `JANAS_AGENT_HOST` / `JANAS_AGENT_PORT` | `127.0.0.1` / 8090 | onde a interface escuta |
| `JANAS_SUMMARY_BASE_URL` / `JANAS_SUMMARY_MODEL` | vazio | outro janas-server só para os resumos (opcional) |

## Segurança

- **Endereços internos bloqueados:** o agente recusa ler `localhost`, `127.0.0.1`, IPs da rede local e endereços reservados, inclusive após redirecionamentos e dentro do Chromium. Assim, alguém com acesso à interface não consegue usá-lo para ler o janas-server nem outros aparelhos da sua rede.
- **Conteúdo das páginas tratado como dado:** o resumo é feito com a instrução de ignorar comandos escritos nas páginas, para reduzir o risco de prompt injection. Nenhum filtro é perfeito; desconfie de respostas estranhas vindas de sites duvidosos.
- **Quem tem o token usa o seu PC:** cada pergunta consome CPU, RAM e a sua conexão. Compartilhe o token só com quem você confia, e troque-o se ele vazar.

## Problemas comuns

- **`CERTIFICATE_VERIFY_FAILED` no setup:** antivírus que inspecionam HTTPS (Avast, AVG, Kaspersky) ou proxies corporativos reassinam os certificados com uma raiz própria. O `setup-agent.ps1` contorna isso usando as raízes confiáveis do Windows, e o scraper usa o repositório de certificados do Windows (`truststore`).
- **"janas-server offline":** o Terminal 1 não está rodando, ainda está carregando o modelo, ou está em outra porta. Nesse caso, use `-BaseUrl`.
- **"Na fila do janas-server":** o servidor atende uma requisição por vez. Com vários navegadores ao mesmo tempo, as perguntas esperam a vez.
- **A primeira página dinâmica demora ~7 s:** é o Chromium abrindo. As seguintes reaproveitam o navegador aberto.
- **Uma pesquisa trouxe fontes fracas:** a busca do ddgs alterna entre mecanismos a cada chamada, e às vezes um deles devolve resultados ruins. Reformular a pergunta, ou pedir explicitamente "pesquise de novo", costuma resolver.
- **Sites que bloqueiam robôs** (proteção anti-bot, paywall) podem falhar mesmo no Chromium. O agente pula para o próximo resultado.
- **`pip` falha ao instalar o `mcp` (`InvalidChunkLength` ou "No matching distribution"):** alguns antivírus com inspeção HTTPS (o Avast, por exemplo) cortam a página do PyPI que lista as versões do pacote `mcp`, que é grande. Instale pelo endereço direto do arquivo: pegue a URL do `.whl` em `https://pypi.org/pypi/mcp/json` (campo `urls`) e rode `.venv\Scripts\python.exe -m pip install <URL do .whl>`. As dependências vêm normalmente.
- **Servidor MCP com ponto vermelho no Cline:** confira se os caminhos do `command` e do `args` existem (rode `configurar-cline.ps1` de novo depois de mover a pasta) e se o `setup-agent.ps1` foi rodado. O erro aparece na lista de servidores do Cline.
- **Cline: erro 400 "only text parts are supported":** *Supports Images* está marcado e o Cline mandou uma imagem (por exemplo, uma captura de tela). Desmarque nas configurações do modelo.
- **Cline: a ferramenta falha com "timeout" depois de 60 s:** falta `"timeout": 300` no bloco do servidor no `cline_mcp_settings.json` (ou o valor de *Network Timeout* na lista de servidores MCP).
- **Cline: o modelo repete a mesma linha ou o mesmo trecho em loop:** suba a *Temperature* para 0.5-0.7.
- **Cline: nenhuma resposta, ou erro de conexão:** o janas-server não está rodando, ainda está carregando o modelo, ou a Base URL está errada. Ela é `http://127.0.0.1:8080/v1`, com `/v1` no fim, e não a 8090.
- **Playwright ou Chromium ausente:** o agente continua funcionando só com páginas estáticas e avisa na etapa da página. Rode `setup-agent.ps1` de novo.
