$ErrorActionPreference = 'Stop'

$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$memory = Get-CimInstance Win32_OperatingSystem

[pscustomobject]@{
    CPU = $processor.Name.Trim()
    Nucleos = $processor.NumberOfCores
    Threads = $processor.NumberOfLogicalProcessors
    Windows = $operatingSystem.Caption
    Build = $operatingSystem.BuildNumber
    RAM_Total_GB = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 1)
    RAM_Livre_GB = [math]::Round($memory.FreePhysicalMemory / 1MB, 1)
} | Format-List

Write-Host 'Memoria fisica:'
Get-CimInstance Win32_PhysicalMemory |
    ForEach-Object {
        [pscustomobject]@{
            Capacidade_GB = [math]::Round($_.Capacity / 1GB, 0)
            Velocidade_MHz = $_.Speed
            Fabricante = $_.Manufacturer
            PartNumber = $_.PartNumber
        }
    } | Format-Table -AutoSize

Write-Host 'GPUs Vulkan/Windows:'
Get-CimInstance Win32_VideoController |
    Select-Object Name, DriverVersion |
    Format-Table -AutoSize

if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host 'NVIDIA:'
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
}

Write-Host 'Discos:'
Get-PhysicalDisk |
    ForEach-Object {
        [pscustomobject]@{
            Nome = $_.FriendlyName
            Tipo = $_.MediaType
            Barramento = $_.BusType
            Tamanho_GB = [math]::Round($_.Size / 1GB, 0)
            Estado = $_.HealthStatus
        }
    } | Format-Table -AutoSize

Write-Host 'Espaco livre por unidade:'
Get-Volume |
    Where-Object DriveLetter |
    ForEach-Object {
        [pscustomobject]@{
            Unidade = "$($_.DriveLetter):"
            Nome = $_.FileSystemLabel
            Livre_GB = [math]::Round($_.SizeRemaining / 1GB, 1)
            Total_GB = [math]::Round($_.Size / 1GB, 0)
        }
    } | Format-Table -AutoSize

if (Get-Command vulkaninfo -ErrorAction SilentlyContinue) {
    Write-Host 'Resumo Vulkan:'
    vulkaninfo --summary
} else {
    Write-Warning 'vulkaninfo nao encontrado. Instale o Vulkan SDK ou use vkcheck.exe do pacote Janas, se disponivel.'
}
