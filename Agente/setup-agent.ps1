<#
.SYNOPSIS
    Cria um ambiente virtual Python isolado para o agente do Janas e instala
    as dependências SOMENTE dentro dele (não mexe no Python do sistema).

.DESCRIPTION
    Roda uma única vez (ou de novo, se quiser recriar o ambiente do zero).
    Precisa de um Python 3.9+ já instalado e acessível como "python" ou "py"
    no PATH -- este script não instala Python, só cria o venv.
#>

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPath = Join-Path $agentRoot '.venv'
$requirements = Join-Path $agentRoot 'requirements.txt'

function Resolve-PythonLauncher {
    foreach ($candidate in @('py', 'python')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $candidate }
    }
    throw 'Python nao encontrado no PATH. Instale o Python 3.9+ (python.org) antes de continuar.'
}

$pythonLauncher = Resolve-PythonLauncher

if (Test-Path -LiteralPath $venvPath) {
    Write-Host "Ambiente virtual ja existe em $venvPath -- reinstalando dependencias."
}
else {
    Write-Host "Criando ambiente virtual isolado em $venvPath ..."
    & $pythonLauncher -m venv $venvPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao criar o ambiente virtual.'
    }
}

$venvPython = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    throw "python.exe nao encontrado dentro do venv ($venvPython)."
}

Write-Host 'Instalando dependencias dentro do venv (isolado do Python do sistema)...'
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao instalar dependencias.'
}

Write-Host ''
Write-Host 'Pronto. Para conversar com o agente, rode:'
Write-Host '  .\run-agent.ps1'