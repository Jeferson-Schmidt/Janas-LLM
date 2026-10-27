<#
.SYNOPSIS
    Mostra a configuracao para usar o agente v2 no Cline (VS Code) com o modelo
    local do janas-server, sem custo. So imprime: nao altera nenhum arquivo.

.DESCRIPTION
    Gera, com os caminhos desta maquina:
      1. o bloco do servidor MCP "janas-pesquisa" (web_research e fetch_url),
         para colar no cline_mcp_settings.json;
      2. os valores do provedor "OpenAI Compatible" apontando para o janas-server.

.PARAMETER BaseUrl
    URL da API do janas-server. Padrao http://127.0.0.1:8080/v1

.PARAMETER NoSummarize
    Devolve ao Cline o texto filtrado das paginas, sem a chamada de resumo no
    janas-server: cerca de 1 minuto mais rapido por pesquisa, mas ocupa mais
    contexto do modelo.
#>

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/v1',
    [switch]$NoSummarize
)

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPython = Join-Path $agentRoot '.venv\Scripts\python.exe'
$serverScript = Join-Path $agentRoot 'mcp_server.py'

if (-not (Test-Path -LiteralPath $venvPython)) {
    throw 'Ambiente virtual nao encontrado. Rode primeiro: .\setup-agent.ps1'
}

$config = [ordered]@{
    mcpServers = [ordered]@{
        'janas-pesquisa' = [ordered]@{
            command     = $venvPython
            args        = @($serverScript)
            env         = [ordered]@{
                JANAS_BASE_URL      = $BaseUrl
                JANAS_MCP_SUMMARIZE = $(if ($NoSummarize) { 'off' } else { 'on' })
            }
            disabled    = $false
            # Uma pesquisa leva 1-2 minutos em CPU; o padrao do Cline (60 s) corta antes.
            timeout     = 300
            autoApprove = @()
        }
    }
}

Write-Host ''
Write-Host '=== 1. Servidor MCP (cole no cline_mcp_settings.json) ===' -ForegroundColor Cyan
Write-Host 'No Cline: icone "MCP Servers" > aba "Installed" > "Configure MCP Servers".'
Write-Host 'Se o arquivo ja tiver outros servidores, acrescente so o bloco "janas-pesquisa".'
Write-Host ''
$config | ConvertTo-Json -Depth 5
Write-Host ''
Write-Host '=== 2. Provedor do modelo (engrenagem do Cline > API Configuration) ===' -ForegroundColor Cyan
Write-Host '  API Provider  : OpenAI Compatible'
Write-Host "  Base URL      : $BaseUrl"
Write-Host '  API Key       : local   (qualquer texto; o janas-server so confere se iniciado com --api-key)'
Write-Host '  Model ID      : janas   (qualquer nome; o servidor usa o modelo que carregou)'
Write-Host '  Context Window: 65536   (o mesmo -Context do run-chat-web.ps1)'
Write-Host '  Supports Images: desligado'
Write-Host ''
Write-Host 'Pre-requisito: o janas-server rodando em outro terminal (.\scripts\run-chat-web.ps1).'
Write-Host 'O Cline inicia o servidor MCP sozinho; o run-agent-web.ps1 nao e necessario para isso.'
