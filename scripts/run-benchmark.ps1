param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3-4b',
    [switch]$CpuOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$binaryDirectory = Join-Path $projectRoot 'bin'
$modelDirectory = Join-Path $projectRoot 'models'
$resultDirectory = Join-Path $projectRoot 'results'
$benchmarkExecutable = Get-ChildItem -LiteralPath $binaryDirectory -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('janas-bench.exe', 'janas-bench') } |
    Select-Object -First 1

if (-not $benchmarkExecutable) {
    throw 'janas-bench nao encontrado. Execute primeiro .\scripts\install-janas.ps1.'
}

New-Item -ItemType Directory -Path $modelDirectory, $resultDirectory -Force | Out-Null
$previousModels = $env:JANAS_MODELS
$previousGpu = $env:JANAS_GPU
$env:JANAS_MODELS = $modelDirectory

try {
    if ($CpuOnly) {
        $env:JANAS_GPU = '0'
        Write-Host "Executando $Model sem GPU."
    } else {
        Remove-Item Env:JANAS_GPU -ErrorAction SilentlyContinue
        Write-Host "Executando $Model com a selecao automatica de CPU/GPU do Janas."
    }

    Push-Location $resultDirectory
    try {
        & $benchmarkExecutable.FullName $Model '--reserve' '8'
        if ($LASTEXITCODE -ne 0) {
            throw "janas-bench terminou com codigo $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
} finally {
    if ($null -eq $previousModels) {
        Remove-Item Env:JANAS_MODELS -ErrorAction SilentlyContinue
    } else {
        $env:JANAS_MODELS = $previousModels
    }

    if ($null -eq $previousGpu) {
        Remove-Item Env:JANAS_GPU -ErrorAction SilentlyContinue
    } else {
        $env:JANAS_GPU = $previousGpu
    }
}
