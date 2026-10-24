<#
.SYNOPSIS
    Inicia a interface web do agente v2 (http://127.0.0.1:8090).

.DESCRIPTION
    Pre-requisito: o janas-server rodando em OUTRO terminal, por exemplo:
        .\scripts\run-chat-web.ps1 -Model qwen3.6-35b-a3b
    O agente descobre sozinho qual modelo o servidor carregou.

    O token de acesso aparece neste terminal ao iniciar. Para acesso externo,
    em um terceiro terminal, na raiz do projeto:
        .\cloudflared.exe tunnel --url http://127.0.0.1:8090

.PARAMETER Port
    Porta da interface web. Padrao 8090.

.PARAMETER BaseUrl
    URL da API do janas-server. Padrao http://127.0.0.1:8080/v1

.PARAMETER Lan
    Escuta em 0.0.0.0 para acesso direto de outros aparelhos da rede local.
    Nao e necessario para o cloudflared.
#>

param(
    [int]$Port = 8090,
    [string]$BaseUrl = 'http://127.0.0.1:8080/v1',
    [switch]$Lan
)

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPython = Join-Path $agentRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $venvPython)) {
    throw 'Ambiente virtual nao encontrado. Rode primeiro: .\setup-agent.ps1'
}

$variables = @{
    JANAS_BASE_URL           = $BaseUrl
    JANAS_AGENT_PORT         = "$Port"
    JANAS_AGENT_HOST         = $(if ($Lan) { '0.0.0.0' } else { '127.0.0.1' })
    PLAYWRIGHT_BROWSERS_PATH = (Join-Path $agentRoot '.venv\browsers')
}
$previous = @{}
foreach ($name in $variables.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
}

try {
    & $venvPython (Join-Path $agentRoot 'web_app.py')
}
finally {
    foreach ($name in $variables.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
