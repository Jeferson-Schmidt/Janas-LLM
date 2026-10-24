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
| Compactação automática (uma vez, quando o contexto enche) | ~40 s |

Em CPU, ler o prompt (~50 tokens/s neste PC) e gerar texto (~7-10 tokens/s) custam muito mais que a internet. Por isso o agente filtra as páginas sem LLM antes de mandá-las ao modelo.

### Resumo ou modo direto?

O resumo das páginas economiza **contexto**, mas não **tempo**: o modelo precisa ler as páginas e ainda escrever o resumo, e escrever é a etapa mais lenta. Há duas opções em [config.py](config.py):

- `SUMMARIZE_PAGES = True` (padrão): cada pesquisa ocupa ~400 tokens da conversa. Cabem dezenas de pesquisas antes de compactar.
- `SUMMARIZE_PAGES = False` (modo direto): os trechos filtrados entram direto na conversa, sem a chamada de resumo. A estimativa, feita a partir dos tempos medidos acima, é economizar ~30-40 s por pesquisa, mas cada pesquisa ocupa ~2.500 tokens.

Se a prioridade é velocidade, experimente o modo direto. Também ajudam: reduzir `CHARS_PER_PAGE` (menos texto lido por página) ou `PAGES_PER_SEARCH`.

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
- **Playwright ou Chromium ausente:** o agente continua funcionando só com páginas estáticas e avisa na etapa da página. Rode `setup-agent.ps1` de novo.
