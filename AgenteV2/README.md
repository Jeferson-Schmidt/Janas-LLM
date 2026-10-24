# Agente Janas v2

Agente que conversa com o janas-server e pesquisa na internet quando a pergunta depende de informação atual. Tem interface web com o uso de tokens e acesso externo protegido por token.

A versão anterior continua em `../Agente/` e na tag git `agente-v1`.

## Como rodar (três terminais)

```
[Terminal 1] janas-server   127.0.0.1:8080   (só neste PC, sem senha)
[Terminal 2] agente v2      127.0.0.1:8090   (interface web, com token)
[Terminal 3] cloudflared    túnel para a porta 8090 (opcional, acesso externo)
```

Uma vez só, para instalar o ambiente:

```powershell
cd "D:\Janas LLM\AgenteV2"
.\setup-agent.ps1
```

O script cria um venv isolado em `.venv\` e instala nele as dependências e o Chromium do Playwright (~150 MB, em `.venv\browsers\`). O Python do sistema não é alterado. Apagar a pasta `.venv` remove tudo.

**Terminal 1**: o janas-server, com o 35B ou o 80B:

```powershell
cd "D:\Janas LLM"
.\scripts\run-chat-web.ps1 -Model qwen3.6-35b-a3b
# ou: .\scripts\run-chat-web.ps1 -Model qwen3-next-80b-a3b-q
```

**Terminal 2**: o agente:

```powershell
cd "D:\Janas LLM\AgenteV2"
.\run-agent-web.ps1      # interface web em http://127.0.0.1:8090
# ou .\run-agent.ps1     # a mesma coisa, no terminal
```

O agente descobre sozinho qual modelo o servidor carregou (`GET /v1/models`). Para trocar entre 35B e 80B, reinicie só o Terminal 1. Se o servidor estiver desligado, a interface mostra "janas-server offline" e volta a funcionar quando ele subir.

**Terminal 3** (opcional): o acesso externo:

```powershell
cd "D:\Janas LLM"
.\cloudflared.exe tunnel --url http://127.0.0.1:8090
```

O cloudflared mostra um endereço `https://xxxx.trycloudflare.com`. **Não use a porta 8080 no túnel**: o janas-server não tem senha.

## Token de acesso

- **Onde fica no código:** a função `get_access_token()` em [config.py](config.py) decide o token, e [web_app.py](web_app.py) o verifica (middleware `autenticacao`).
- **De onde vem**, em ordem:
  1. da variável de ambiente `JANAS_AGENT_TOKEN`, se estiver definida;
  2. senão, do arquivo `AgenteV2\.token`;
  3. senão, o agente gera um token aleatório na primeira execução e grava em `.token`.

  O arquivo `.token` está no `.gitignore` e nunca vai para o git.
- **Onde ver:** o token aparece no Terminal 2 sempre que o agente inicia, junto com o link pronto.
- **Como entrar:**
  - Abra `https://xxxx.trycloudflare.com/?token=SEU_TOKEN`, ou `http://127.0.0.1:8090/?token=SEU_TOKEN` neste PC.
  - Ou abra o endereço sem o token e digite-o na tela de login.

  O navegador guarda um cookie por 30 dias (`HttpOnly`, e `Secure` quando o acesso é via https) e a URL fica limpa.
- **Trocar o token:** apague o `.token` e reinicie o agente; um novo é gerado. Os navegadores que usavam o antigo precisam entrar de novo. Para um token fixo seu: `$env:JANAS_AGENT_TOKEN = 'seu-token-longo'` antes do `run-agent-web.ps1`.
- **Proteções:**
  - depois de 10 tentativas erradas, o IP fica bloqueado por 10 minutos (pelo túnel, o IP real vem do cabeçalho `CF-Connecting-IP`);
  - chamadas à API sem o cookie, ou sem `Authorization: Bearer SEU_TOKEN`, recebem 401.
- **Uma conversa por navegador:** cada navegador recebe o próprio cookie de sessão, então o celular e o PC têm históricos separados. As conversas ficam só na memória do agente e somem quando ele é reiniciado.

## Como uma pergunta é respondida

```
pergunta → modelo decide → web_research(consulta)
                               ├─ busca (DuckDuckGo/ddgs, ~2 s)
                               ├─ baixa ~8 resultados em paralelo (httpx + trafilatura)
                               ├─ página quase vazia? abre no Chromium (JavaScript)
                               ├─ escolhe as 3 páginas mais relevantes pelo conteúdo (BM25, sem LLM)
                               ├─ filtro BM25: só os trechos relevantes (~3.000 caracteres/página)
                               └─ UMA chamada de resumo para as 3 páginas, numa conversa à parte
                           ← só o resumo com as fontes volta para a conversa
           → modelo responde
```

Escolhas de desempenho:

- **A conversa só cresce no fim.** O Qwen3.6 e o Qwen3-Next têm estado recorrente: se uma mensagem antiga muda, o janas-server relê a conversa inteira. Por isso a data do prompt de sistema fica fixa na sessão, a lista de ferramentas nunca muda (para proibir ferramentas o agente usa `tool_choice: none`) e a resposta parcial de um "Parar" também fica no histórico. Resultado: cada turno lê só o que é novo, e a interface mostra isso em "reaproveitados (cache)".
- **Memória de pesquisa separada da memória de conversa.** O resultado completo de cada pesquisa (fontes, método estático/dinâmico, tempos, tokens) fica no painel "Memória de pesquisa". A conversa recebe só o resumo curto. Pesquisas repetidas em até 1 h vêm do cache, sem baixar nem resumir de novo.
- **O resumo roda numa conversa separada** no mesmo servidor. O `--keep 8` padrão do janas-server mantém a conversa principal calculada enquanto isso.
- **Compactação automática:** ao passar de 85% do contexto, o agente pede ao modelo um resumo da conversa, acrescentando o pedido no fim (o servidor lê só ele). Depois a conversa recomeça a partir do resumo.

## Configuração ([config.py](config.py))

| Valor | Padrão | O que faz |
|---|---|---|
| `CONTEXT_WINDOW` | 65535 | contexto considerado na barra e na compactação. Se o servidor tiver `--ctx` menor, vale o menor. Também por `JANAS_CONTEXT_WINDOW`. |
| `COMPACT_AT` | 0.85 | fração do contexto que dispara a compactação |
| `PAGES_PER_SEARCH` | 3 | páginas lidas e resumidas por pesquisa |
| `SEARCH_RESULTS` | 8 | resultados pedidos à busca (sobram para quando uma página falha) |
| `CHARS_PER_PAGE` | 3000 | caracteres por página enviados ao resumo depois do filtro (~800 tokens) |
| `SUMMARIZE_PAGES` | True | `False` = modo direto: os trechos filtrados entram na conversa sem a chamada de resumo (mais rápido, ocupa mais contexto) |
| `SUMMARY_MAX_TOKENS` | 350 | tamanho máximo do resumo de uma pesquisa |
| `DYNAMIC_MIN_CHARS` | 800 | abaixo disso, a página é aberta no Chromium |
| `ANSWER_MAX_TOKENS` | 1500 | tamanho máximo de uma resposta |
| `THINK_DEFAULT` | off | raciocínio; também há um botão na interface |
| `JANAS_SUMMARY_BASE_URL` | vazio | outro janas-server só para os resumos (opcional) |

## Problemas conhecidos

- **Certificado SSL no setup (`CERTIFICATE_VERIFY_FAILED`):** o Avast desta máquina inspeciona HTTPS. O `setup-agent.ps1` contorna isso usando as raízes confiáveis do Windows, e o scraper usa o repositório de certificados do Windows (`truststore`).
- **A primeira página dinâmica demora ~7 s**, porque o Chromium está abrindo. As seguintes reaproveitam o navegador aberto.
- **Sites que bloqueiam robôs** (Cloudflare, paywall) podem falhar mesmo no Chromium. O agente pula para o próximo resultado.
