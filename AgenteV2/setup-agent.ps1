<#
.SYNOPSIS
    Cria o ambiente virtual Python isolado do agente v2 e instala as
    dependencias SOMENTE dentro dele, incluindo o Chromium do Playwright
    (usado para paginas dinamicas). Nao mexe no Python do sistema.

.DESCRIPTION
    Roda uma vez (ou de novo para atualizar). Precisa de Python 3.10+ no PATH
    como "py" ou "python". O Chromium (~150 MB) fica dentro de .venv\browsers,
    entao apagar a pasta .venv remove tudo.
#>

$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$venvPath = Join-Path $agentRoot '.venv'
$requirements = Join-Path $agentRoot 'requirements.txt'

function Resolve-PythonLauncher {
    foreach ($candidate in @('py', 'python')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    throw 'Python nao encontrado no PATH. Instale o Python 3.10+ (python.org) antes de continuar.'
}

if (Test-Path -LiteralPath $venvPath) {
    Write-Host "Ambiente virtual ja existe em $venvPath -- atualizando dependencias."
}
else {
    $pythonLauncher = Resolve-PythonLauncher
    Write-Host "Criando ambiente virtual isolado em $venvPath ..."
    & $pythonLauncher -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar o ambiente virtual.' }
}

$venvPython = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    throw "python.exe nao encontrado dentro do venv ($venvPython)."
}

Write-Host 'Atualizando o pip dentro do venv...'
& $venvPython -m pip install --upgrade pip --quiet
# O pip sai com codigo 0 mesmo sem conseguir baixar; por isso confere a versao.
$pipLine = & $venvPython -m pip --version | Select-String '^pip (\d+\.\d+)' | Select-Object -First 1
$pipVersion = [version]$pipLine.Matches[0].Groups[1].Value
if ($pipVersion -lt [version]'24.2') {
    # Antivirus com inspecao de HTTPS (Avast, Kaspersky, proxy corporativo)
    # reassinam os certificados com uma raiz que so existe no repositorio do
    # Windows. O pip antigo do venv nao le esse repositorio; o novo (24.2+) le.
    # Entao exporta as raizes do Windows para um PEM temporario so para
    # atualizar o pip; dali em diante ele usa o repositorio do Windows sozinho.
    Write-Host 'Falha de certificado; tentando com as raizes confiaveis do Windows...'
    $bundle = Join-Path ([IO.Path]::GetTempPath()) 'janas-agent-roots.pem'
    # Pela entrada padrao: o PowerShell 5.1 remove aspas de argumentos -c.
    $exportRoots = @'
import ssl, sys
pems = [ssl.DER_cert_to_PEM_cert(cert) for store in ("ROOT", "CA")
        for cert, encoding, _ in ssl.enum_certificates(store) if encoding == "x509_asn"]
open(sys.argv[1], "w").write("".join(pems))
'@
    $exportRoots | & $venvPython - $bundle
    try {
        & $venvPython -m pip install --upgrade pip --quiet --cert $bundle
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao atualizar o pip.' }
    }
    finally {
        Remove-Item -LiteralPath $bundle -ErrorAction SilentlyContinue
    }
}

Write-Host 'Instalando dependencias dentro do venv...'
& $venvPython -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependencias.' }

Write-Host 'Instalando o Chromium do Playwright dentro do venv (paginas dinamicas)...'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $venvPath 'browsers'
try {
    & $venvPython -m playwright install chromium
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Chromium nao instalado: o agente funciona, mas so com paginas estaticas.'
    }
}
finally {
    Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Pronto. Com o janas-server rodando em outro terminal:'
Write-Host '  .\run-agent-web.ps1   (interface web em http://127.0.0.1:8090)'
Write-Host '  .\run-agent.ps1       (terminal)'
