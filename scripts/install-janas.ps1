param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$downloadDirectory = Join-Path $projectRoot 'downloads'
$installDirectory = Join-Path $projectRoot 'bin'
$archivePath = Join-Path $downloadDirectory 'janas-windows-x86_64.zip'
$releaseUrl = 'https://github.com/prabanta-dev/janas/releases/latest/download/janas-windows-x86_64.zip'

if (Test-Path -LiteralPath $installDirectory) {
    $existingItems = @(Get-ChildItem -LiteralPath $installDirectory -Force)
    if ($existingItems.Count -gt 0 -and -not $Force) {
        throw 'A pasta bin ja contem arquivos. Revise-a ou execute novamente com -Force para atualizar.'
    }
}

New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Write-Host "Baixando o release oficial: $releaseUrl"
Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath
Expand-Archive -LiteralPath $archivePath -DestinationPath $installDirectory -Force:$Force

$chatExecutable = Get-ChildItem -LiteralPath $installDirectory -Recurse -File |
    Where-Object { $_.Name -in @('janas-chat.exe', 'janas-chat') } |
    Select-Object -First 1

if (-not $chatExecutable) {
    throw "O ZIP foi extraido, mas janas-chat nao foi encontrado em $installDirectory. Confira o conteudo do release."
}

Write-Host "Janas instalado em: $($chatExecutable.DirectoryName)"
Write-Host 'Nenhum modelo foi baixado. Os modelos serao guardados em models/ quando voce executar um benchmark.'
