param(
    [ValidateSet('qwen3.6-35b-a3b', 'qwen3-next-80b-a3b-q')]
    [string]$Model = 'qwen3.6-35b-a3b',
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 65536,
    [switch]$Gpu
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
$previousModels = $env:JANAS_MODELS
$previousGpu = $env:JANAS_GPU
$previousGpuDevice = $env:JANAS_GPU_DEVICE

if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw 'janas-server nao encontrado. Execute primeiro .\scripts\install-janas.ps1.'
}
if (-not $modelFile) {
    throw "Modelo $Model nao encontrado em models/. Baixe-o primeiro com janas-get.exe."
}

$env:JANAS_MODELS = $modelDirectory

try {
    Write-Host "Janas Chat Web ($Model, contexto $Context): http://127.0.0.1:8080/test"
    $serverArguments = @($modelFile.FullName, '--host', '127.0.0.1', '--port', '8080', '--test', '--ctx', "$Context", '--reserve', '8', '--no-mcp', '--no-store')
    if ($Gpu) {
        Remove-Item Env:JANAS_GPU -ErrorAction SilentlyContinue
        $env:JANAS_GPU_DEVICE = 'discrete'
        Write-Host 'GPU discreta habilitada; 8 GiB reservados; armazenamento de conversas desativado.'
    }
    else {
        $env:JANAS_GPU = '0'
        Remove-Item Env:JANAS_GPU_DEVICE -ErrorAction SilentlyContinue
        $serverArguments += '--no-gpu'
        Write-Host 'CPU-only; 8 GiB reservados; armazenamento de conversas desativado.'
    }

    & $serverExecutable @serverArguments
    if ($LASTEXITCODE -ne 0) {
        throw "janas-server terminou com codigo $LASTEXITCODE."
    }
}
finally {
    if ($null -eq $previousModels) {
        Remove-Item Env:JANAS_MODELS -ErrorAction SilentlyContinue
    }
    else {
        $env:JANAS_MODELS = $previousModels
    }

    if ($null -eq $previousGpu) {
        Remove-Item Env:JANAS_GPU -ErrorAction SilentlyContinue
    }
    else {
        $env:JANAS_GPU = $previousGpu
    }

    if ($null -eq $previousGpuDevice) {
        Remove-Item Env:JANAS_GPU_DEVICE -ErrorAction SilentlyContinue
    }
    else {
        $env:JANAS_GPU_DEVICE = $previousGpuDevice
    }
}
