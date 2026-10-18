param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3-4b',
    [switch]$CpuOnly,
    [switch]$Tune
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$binaryDirectory = Join-Path $projectRoot 'bin'
$modelDirectory = Join-Path $projectRoot 'models'
$previousCodePage = $null
$codePageOutput = & chcp.com
if ($codePageOutput -match '(\d+)\s*$') {
    $previousCodePage = $Matches[1]
}
$previousInputEncoding = [Console]::InputEncoding
$previousOutputEncoding = [Console]::OutputEncoding
$previousPipelineEncoding = $OutputEncoding
$utf8Encoding = New-Object System.Text.UTF8Encoding($false)

$previousGpu = $env:JANAS_GPU
$chatExecutable = Get-ChildItem -LiteralPath $binaryDirectory -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('janas-chat.exe', 'janas-chat') } |
    Select-Object -First 1

if (-not $chatExecutable) {
    throw 'janas-chat nao encontrado. Execute primeiro .\scripts\install-janas.ps1.'
}

New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null
$previousModels = $env:JANAS_MODELS
$env:JANAS_MODELS = $modelDirectory

try {
    & chcp.com 65001 | Out-Null
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
    $OutputEncoding = $utf8Encoding

    if ($CpuOnly) {
        $env:JANAS_GPU = '0'
        Write-Host "Abrindo $Model somente na CPU, com 8 GiB reservados fora do cache."
    } else {
        Remove-Item Env:JANAS_GPU -ErrorAction SilentlyContinue
        Write-Host "Abrindo $Model com selecao automatica de GPU e 8 GiB reservados fora do cache."
    }

    $chatArguments = @($Model, '--reserve', '8')
    if (-not $Tune) {
        $chatArguments += '--no-tune'
    }

    $chatProcess = Start-Process -FilePath $chatExecutable.FullName -ArgumentList $chatArguments -NoNewWindow -Wait -PassThru
    if ($chatProcess.ExitCode -ne 0) {
        throw "janas-chat terminou com codigo $($chatProcess.ExitCode)."
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

    if ($previousCodePage) {
        & chcp.com $previousCodePage | Out-Null
    }

    [Console]::InputEncoding = $previousInputEncoding
    [Console]::OutputEncoding = $previousOutputEncoding
    $OutputEncoding = $previousPipelineEncoding
}
