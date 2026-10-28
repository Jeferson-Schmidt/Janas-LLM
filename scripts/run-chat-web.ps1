param(
    [ValidateSet('qwen3.6-35b-a3b', 'qwen3-next-80b-a3b-q')]
    [string]$Model = 'qwen3.6-35b-a3b',
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 65536,
    [switch]$Gpu,
    # Memoria (GiB) para o cache de especialistas do Janas. 0 (padrao) =
    # automatico, como antes: o Janas escolhe o tamanho e deixa --reserve 8 GiB
    # para os outros programas. Com um valor, o cache fica fixo nesse tamanho.
    [ValidateRange(0, 1024)]
    [double]$Cache = 0,
    # Mostra o comando e os limites de memoria sem iniciar o servidor.
    [switch]$DryRun
)

# Limites do -Cache. Com --cache explicito o Janas NAO aplica o --reserve,
# entao quem protege os outros programas e este script:
#   - teto fixo: metade da RAM. O autor do Janas mede o Qwen3-Next-80B com
#     12-16 GiB de cache numa maquina de 32 GB; acima disso o ganho e pequeno
#     (os especialistas mais usados ja cabem) e sobra menos RAM para o cache de
#     arquivos do Windows, que tambem acelera a leitura do SSD;
#   - limite do momento: a RAM disponivel agora menos uma margem, que cobre o
#     que o janas-server usa alem do cache (pesos fora dos especialistas, estado
#     do contexto, conversas mantidas: ~4 GiB) e folga para os programas abertos
#     crescerem (~2 GiB).
$CacheMaxFractionOfRam = 0.50
$CacheSafetyMarginGiB = 6
$CacheMinGiB = 1

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

function Get-CacheLimit {
    # Win32_PerfFormattedData_PerfOS_Memory tem o mesmo nome em qualquer idioma
    # do Windows (os contadores do Get-Counter sao traduzidos).
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGiB = $os.TotalVisibleMemorySize / 1MB
    try {
        $availableGiB = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes / 1024
    }
    catch {
        $availableGiB = $os.FreePhysicalMemory / 1MB
    }
    # Truncados a 0,1 GiB, para nunca mostrar um limite maior que o real.
    $fixedCapGiB = [math]::Floor($totalGiB * $CacheMaxFractionOfRam * 10) / 10
    $nowCapGiB = [math]::Floor(($availableGiB - $CacheSafetyMarginGiB) * 10) / 10
    [pscustomobject]@{
        TotalGiB     = $totalGiB
        AvailableGiB = $availableGiB
        FixedCapGiB  = $fixedCapGiB
        NowCapGiB    = $nowCapGiB
        MaxGiB       = [math]::Min($fixedCapGiB, $nowCapGiB)
    }
}

if ($Cache -gt 0) {
    $limit = Get-CacheLimit
    $details = ('RAM total {0:N1} GiB; disponivel agora {1:N1} GiB. Limite fixo: {2:P0} da RAM = {3:N1} GiB. ' +
        'Limite agora: disponivel - {4} GiB de margem = {5:N1} GiB.') -f
        $limit.TotalGiB, $limit.AvailableGiB, $CacheMaxFractionOfRam, $limit.FixedCapGiB, $CacheSafetyMarginGiB, $limit.NowCapGiB

    if ($Cache -lt $CacheMinGiB) {
        throw "-Cache $Cache GiB e pequeno demais (minimo $CacheMinGiB GiB). Omita -Cache para o modo automatico."
    }
    if ($limit.MaxGiB -lt $CacheMinGiB) {
        throw ("Nao ha memoria livre para um cache fixo agora. $details " +
            'Feche programas pesados (navegador, outros modelos) ou omita -Cache para o modo automatico.')
    }
    if ($Cache -gt $limit.MaxGiB) {
        throw ("-Cache $Cache GiB nao e viavel: o maximo permitido agora e {0:N1} GiB. $details " +
            'Use um valor menor, feche programas para liberar memoria, ou omita -Cache para o modo automatico.') -f $limit.MaxGiB
    }
}

$env:JANAS_MODELS = $modelDirectory

try {
    Write-Host "Janas Chat Web ($Model, contexto $Context): http://127.0.0.1:8080/test"
    $serverArguments = @($modelFile.FullName, '--host', '127.0.0.1', '--port', '8080', '--test', '--ctx', "$Context", '--reserve', '8', '--no-mcp', '--no-store')
    if ($Cache -gt 0) {
        # Ponto como separador decimal, qualquer que seja o idioma do Windows.
        $serverArguments += @('--cache', $Cache.ToString([Globalization.CultureInfo]::InvariantCulture))
        Write-Host ('Cache de especialistas fixo: {0:N1} GiB (maximo permitido agora: {1:N1} GiB).' -f $Cache, $limit.MaxGiB)
    }
    else {
        Write-Host 'Cache de especialistas automatico (o Janas escolhe; use -Cache GiB para fixar).'
    }
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

    if ($DryRun) {
        if ($Cache -le 0) { $limit = Get-CacheLimit }
        Write-Host ('Memoria: RAM {0:N1} GiB, disponivel {1:N1} GiB; -Cache maximo agora {2:N1} GiB.' -f $limit.TotalGiB, $limit.AvailableGiB, $limit.MaxGiB)
        Write-Host "Comando (nao executado): $serverExecutable $($serverArguments -join ' ')"
        return
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
