<#
.SYNOPSIS
    Roda o agente Janas com busca na internet, usando o Python isolado do venv
    (.venv) criado por setup-agent.ps1. Nao usa o Python do sistema.

.DESCRIPTION
    Pre-requisito: o janas-server precisa estar rodando e com um modelo
    carregado, por exemplo com:
        D:\Janas LLM\scripts\run-chat-web.ps1 -Model qwen3.6-35b-a3b

.PARAMETER Model
    Nome do modelo exatamente como foi carregado no janas-server (o agente
    so troca a conversa com o servidor, nao carrega outro modelo).

.PARAMETER BaseUrl
    URL base da API do janas-server. Padrao: http://127.0.0.1:8080/v1
#>

param(
    [string]$Model = 'qwen3.6-35b-a3b',
    [string]$BaseUrl = 'http://127.0.0.1:8080/v1'
)

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPython = Join-Path $agentRoot '.venv\Scripts\python.exe'
$agentScript = Join-Path $agentRoot 'janas-agent.py'

if (-not (Test-Path -LiteralPath $venvPython)) {
    throw "Ambiente virtual nao encontrado. Rode primeiro: .\setup-agent.ps1"
}

$env:JANAS_MODEL = $Model
$env:JANAS_BASE_URL = $BaseUrl

try {
    & $venvPython $agentScript
}
finally {
    Remove-Item Env:JANAS_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:JANAS_BASE_URL -ErrorAction SilentlyContinue
}