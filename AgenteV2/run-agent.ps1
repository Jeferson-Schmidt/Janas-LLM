<#
.SYNOPSIS
    Roda o agente v2 no terminal, com o Python isolado do venv.

.DESCRIPTION
    Pre-requisito: o janas-server rodando em OUTRO terminal, por exemplo:
        .\scripts\run-chat-web.ps1 -Model qwen3.6-35b-a3b
    O agente descobre sozinho qual modelo o servidor carregou.

.PARAMETER BaseUrl
    URL da API do janas-server. Padrao http://127.0.0.1:8080/v1
#>

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/v1'
)

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPython = Join-Path $agentRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $venvPython)) {
    throw 'Ambiente virtual nao encontrado. Rode primeiro: .\setup-agent.ps1'
}

$variables = @{
    JANAS_BASE_URL           = $BaseUrl
    PLAYWRIGHT_BROWSERS_PATH = (Join-Path $agentRoot '.venv\browsers')
}
$previous = @{}
foreach ($name in $variables.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
}

try {
    & $venvPython (Join-Path $agentRoot 'cli.py')
}
finally {
    foreach ($name in $variables.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
