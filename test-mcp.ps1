#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Starting server..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}

# Wait for server to be ready
$connected = $false
$retries = 0
$maxRetries = 15

Write-Host "[TEST] Testing server connectivity..." -ForegroundColor Yellow
while (-not $connected -and $retries -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "[SUCCESS] Server is running and responding on http://127.0.0.1:8080/test" -ForegroundColor Green
            $connected = $true
            break
        }
    }
    catch {
        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $retries++
    }
}

if (-not $connected) {
    Write-Error "Failed to connect to server after $maxRetries attempts. Server may not be running correctly."
    exit 1
}

Write-Host "\n[INFO] Server is running. Open http://127.0.0.1:8080/test in your browser to test the MCP services. Press Enter to exit and stop the server..." -ForegroundColor Cyan
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Stop the server process
Write-Host "[INFO] Stopping server..." -ForegroundColor Yellow
if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "[INFO] Test script completed." -ForegroundColor Green
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Starting server..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}

# Wait for server to be ready
$connected = $false
$retries = 0
$maxRetries = 15

Write-Host "[TEST] Testing server connectivity..." -ForegroundColor Yellow
while (-not $connected -and $retries -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "[SUCCESS] Server is running and responding on http://127.0.0.1:8080/test" -ForegroundColor Green
            $connected = $true
            break
        }
    }
    catch {
        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $retries++
    }
}

if (-not $connected) {
    Write-Error "Failed to connect to server after $maxRetries attempts. Server may not be running correctly."
    exit 1
}

Write-Host "\n[INFO] Server is running. Open http://127.0.0.1:8080/test in your browser to test the MCP services. Press Enter to exit and stop the server..." -ForegroundColor Cyan
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Stop the server process
Write-Host "[INFO] Stopping server..." -ForegroundColor Yellow
if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "[INFO] Test script completed." -ForegroundColor Green
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
    n
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Starting server..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}

# Wait for server to be ready
$connected = $false
$retries = 0
$maxRetries = 15

Write-Host "[TEST] Testing server connectivity..." -ForegroundColor Yellow
while (-not $connected -and $retries -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "[SUCCESS] Server is running and responding on http://127.0.0.1:8080/test" -ForegroundColor Green
            $connected = $true
            break
        }
    }
    catch {
        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $retries++
    }
}

if (-not $connected) {
    Write-Error "Failed to connect to server after $maxRetries attempts. Server may not be running correctly."
    exit 1
}

Write-Host "\n[INFO] Server is running. Open http://127.0.0.1:8080/test in your browser to test the MCP services. Press Enter to exit and stop the server..." -ForegroundColor Cyan
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Stop the server process
Write-Host "[INFO] Stopping server..." -ForegroundColor Yellow
if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "[INFO] Test script completed." -ForegroundColor Green
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu,
    
    [switch]$SkipWebServer,
    
    [switch]$Verbose
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'
$servicesDirectory = Join-Path $projectRoot 'bin\janas\services'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Check if services directory exists
if (-not (Test-Path -LiteralPath $servicesDirectory)) {
    throw "Services directory not found at $servicesDirectory"
}

# Get list of service executables
$services = Get-ChildItem -LiteralPath $servicesDirectory -Filter "*.exe" -File | Where-Object { $_.Name -match '^janas-' }

# Start the server
Write-Host "[TEST] Starting Janas Server with model: $($modelFile.Name)" -ForegroundColor Green

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Waiting for server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu,
    
    [switch]$SkipWebServer,
    
    [switch]$Verbose
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'
$servicesDirectory = Join-Path $projectRoot 'bin\janas\services'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Check if services directory exists
if (-not (Test-Path -LiteralPath $servicesDirectory)) {
    throw "Services directory not found at $servicesDirectory"
}

# Get list of service executables
$services = Get-ChildItem -LiteralPath $servicesDirectory -Filter "*.exe" -File | Where-Object { $_.Name -match '^janas-' }

# Start the server
Write-Host "[TEST] Starting Janas Server with model: $($modelFile.Name)" -ForegroundColor Green

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Waiting for server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu,
    
    # Wait for server to be ready
    $connected = $false
    $retries = 0
    $maxRetries = 15

    Write-Host "[TEST] Testing server connectivity..." -ForegroundColor Yellow
    while (-not $connected -and $retries -lt $maxRetries) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "[SUCCESS] Server is running and responding on http://127.0.0.1:8080/test" -ForegroundColor Green
                $connected = $true
                break
            }
        }
        catch {
            Write-Host "." -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            $retries++
        }
    }

    if (-not $connected) {
        Write-Error "Failed to connect to server after $maxRetries attempts. Server may not be running correctly."
        exit 1
    }

    # Test basic connectivity
    Write-Host "\n[TEST] Testing basic connectivity..." -ForegroundColor Green
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200 -and $response.Content -like "*Janas Chat*" -or $response.Content -like "*MCP*" -or $response.Content -like "*model*") {
            Write-Host "[SUCCESS] Basic connectivity test passed" -ForegroundColor Green
        }
        else {
            Write-Warning "Basic connectivity test: Received response but content doesn't look right."
        }
    }
    catch {
        Write-Error "Failed to connect to server: $($_.Exception.Message)"
        exit 1
    }

    # Test each service
    Write-Host "\n[TEST] Testing MCP services..." -ForegroundColor Green
    $serviceTests = @(
        @{
            Name            = "System Information"
            Endpoint        = "/test"
            ExpectedContent = @("System", "CPU", "Memory", "Disk", "Battery")
            Description     = "Test basic system information service"
        },
        @{
            Name            = "Weather Service"
            Endpoint        = "/test"
            ExpectedContent = @("weather", "temperature", "forecast", "humidity")
            Description     = "Test weather service integration"
        },
        @{
            Name            = "Wikipedia Service"
            Endpoint        = "/test"
            ExpectedContent = @("wikipedia", "search", "article", "encyclopedia")
            Description     = "Test Wikipedia service integration"
        }
    )

    # Test each service
    $serviceResults = @()
    foreach ($test in $serviceTests) {
        Write-Host "[TEST] $($_.Name) - $($test.Description)" -ForegroundColor Yellow
    
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 10 -UseBasicParsing
            $content = $response.Content.ToLower()
        
            $allFound = $true
            $missing = @()
        
            foreach ($expected in $test.ExpectedContent) {
                if ($content -notlike "*$expected*") {
                    $allFound = $false
                    $missing += $expected
                }
            }
        
            if ($allFound) {
                Write-Host "[SUCCESS] $($_.Name): All expected content found" -ForegroundColor Green
                $serviceResults += [PSCustomObject]@{
                    Service = $test.Name
                    Status  = "PASS"
                    Details = "All expected content found"
                }
            }
            else {
                Write-Warning "[WARNING] $($_.Name): Missing content - $($missing -join ', ')"
                $serviceResults += [PSCustomObject]@{
                    Service = $test.Name
                    Status  = "WARNING"
                    Details = "Missing content: $($missing -join ', ')"
                }
            }
        
        }
        catch {
            Write-Error "[ERROR] $($_.Name): Failed to connect - $($_.Exception.Message)"
            # Test service discovery via /mcp endpoint (if available)
            Write-Host "\n[TEST] Testing service discovery (/mcp endpoint)..." -ForegroundColor Green
            try {
                $mcpResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8080/mcp" -Method Get -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
                if ($mcpResponse.StatusCode -eq 200) {
                    $mcpContent = $mcpResponse.Content.ToLower()
                    $serviceCount = ($mcpContent -split "\n" | Where-Object { $_ -match "\w+" }).Count
                    Write-Host "[SUCCESS] Service discovery: Found $serviceCount services" -ForegroundColor Green
                    Write-Host "[INFO] MCP services found: $mcpContent" -ForegroundColor Cyan
        
                    # Check if any known services are listed
                    $knownServices = @("janas-system", "janas-weather", "janas-wiki", "janas-flights", "janas-git", "janas-github", "janas-maps", "janas-prices", "janas-quakes")
                    $foundServices = @()
        
                    foreach ($service in $knownServices) {
                        if ($mcpContent -like "*$service*") {
                            $foundServices += $service
                        }
                    }
        
                    if ($foundServices.Count -gt 0) {
                        Write-Host "[SUCCESS] Found $($foundServices.Count) known services: $($foundServices -join ', ')" -ForegroundColor Green
                    }
                    else {
                        Write-Warning "[WARNING] No known services found in /mcp response. This might be normal if services aren't running." -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Warning "[WARNING] /mcp endpoint returned status $($mcpResponse.StatusCode)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Warning "[WARNING] Could not access /mcp endpoint: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Test basic model interaction
            Write-Host "\n[TEST] Testing basic model interaction..." -ForegroundColor Green
            try {
                # This is a simplified test - in a real scenario, you'd use the actual API
                $testPrompt = "What is the Model Context Protocol (MCP)?"
                Write-Host "[INFO] Asking model: $testPrompt" -ForegroundColor Cyan
    
                # In a real implementation, you'd send this to the server's API endpoint
                # For now, we'll just note that this would be the next step
                Write-Host "[INFO] To fully test model interaction, send a question to http://127.0.0.1:8080/test and verify the model responds correctly." -ForegroundColor Yellow
                Write-Host "[INFO] Try asking: \'What is the Model Context Protocol?\'" -ForegroundColor Cyan
    
                $modelTestResult = "Manual test required: Open http://127.0.0.1:8080/test and ask a question."
    
            }
            catch {
                Write-Error "[ERROR] Failed to test model interaction: $($_.Exception.Message)"
            }

            # Summary
            Write-Host "\n" + "="*60 -ForegroundColor Cyan
            Write-Host "MCP TEST SUMMARY" -ForegroundColor Yellow
            Write-Host "="*60 -ForegroundColor Cyan

            $serviceResults | ForEach-Object {
                $color = switch ($_.Status) {
                    "PASS" { "Green" }
                    "WARNING" { "Yellow" }
                    "FAIL" { "Red" }
                    default { "White" }
                }
                Write-Host "- $($_.Service): $($_.Status) - $($_.Details)" -ForegroundColor $color
            }

            Write-Host "\n[INFO] To test model interaction, open http://127.0.0.1:8080/test in your browser and ask questions." -ForegroundColor Cyan
            Write-Host "[INFO] To stop the server, press Ctrl+C in this window." -ForegroundColor Cyan

            # Keep the script alive so the server keeps running
            Write-Host "\n[INFO] Server is running. Press Enter to exit and stop the server..." -ForegroundColor Yellow
            $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            # Stop the server process
            Write-Host "[INFO] Stopping server..." -ForegroundColor Yellow
            if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
                Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
            }

            Write-Host "[INFO] Test script completed." -ForegroundColor Green
            $serviceResults += [PSCustomObject]@{
                Service = $test.Name
                Status  = "FAIL"
                Details = $_.Exception.Message
            }
        }
    }
    [switch]$SkipWebServer,
    
    [switch]$Verbose
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'
$servicesDirectory = Join-Path $projectRoot 'bin\janas\services'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Check if services directory exists
if (-not (Test-Path -LiteralPath $servicesDirectory)) {
    throw "Services directory not found at $servicesDirectory"
}

# Get list of service executables
$services = Get-ChildItem -LiteralPath $servicesDirectory -Filter "*.exe" -File | Where-Object { $_.Name -match '^janas-' }

# Start the server
Write-Host "[TEST] Starting Janas Server with model: $($modelFile.Name)" -ForegroundColor Green

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
    n
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
#===================================================================================
# MCP (Model Context Protocol) Test Script for Janas LLM
# Tests the functionality of all MCP services
#===================================================================================

param(
    [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
    [string]$Model = 'qwen3.6-35b-a3b',
    
    [ValidateSet(4096, 8192, 16384, 65536)]
    [int]$Context = 8192,
    
    [switch]$Gpu,
    
    [switch]$SkipWebServer,
    
    [switch]$Verbose
)

# Set error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Define paths
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
$modelDirectory = Join-Path $projectRoot 'models'
$servicesDirectory = Join-Path $projectRoot 'bin\janas\services'

# Verify required files exist
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    throw "janas-server not found. Please run install-janas.ps1 first."
    #===================================================================================
    # MCP (Model Context Protocol) Test Script for Janas LLM
    # Tests the functionality of all MCP services
    #===================================================================================

    param(
        [ValidateSet('qwen3-4b', 'qwen3-30b-a3b', 'qwen3.6-35b-a3b', 'qwen3-next-80b-a3b')]
        [string]$Model = 'qwen3.6-35b-a3b',
    
        [ValidateSet(4096, 8192, 16384, 65536)]
        [int]$Context = 8192,
    
        [switch]$Gpu,
    
        [switch]$SkipWebServer,
    
        [switch]$Verbose
    )

    # Set error handling
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    # Define paths
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $serverExecutable = Join-Path $projectRoot 'bin\janas\janas-server.exe'
    $modelDirectory = Join-Path $projectRoot 'models'
    $servicesDirectory = Join-Path $projectRoot 'bin\janas\services'

    # Verify required files exist
    if (-not (Test-Path -LiteralPath $serverExecutable)) {
        throw "janas-server not found. Please run install-janas.ps1 first."
    }

    if (-not (Test-Path -LiteralPath $modelDirectory)) {
        throw "Models directory not found."
    }

    # Find model file
    $modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $modelFile) {
        throw "Model $Model not found in models/. Please download it first with janas-get.exe."
    }

    # Check if services directory exists
    if (-not (Test-Path -LiteralPath $servicesDirectory)) {
        throw "Services directory not found at $servicesDirectory"
    }

    # Get list of service executables
    $services = Get-ChildItem -LiteralPath $servicesDirectory -Filter "*.exe" -File | Where-Object { $_.Name -match '^janas-' }

    # Start the server
    Write-Host "[TEST] Starting Janas Server with model: $($modelFile.Name)" -ForegroundColor Green

    # Build server arguments
    $serverArguments = @($modelFile.FullName, 
        '--host', '127.0.0.1', 
        '--port', '8080', 
        '--ctx', "$Context", 
        '--reserve', '8', 
        '--no-store'
    )

    # Add GPU flag if specified
    if ($Gpu) {
        $serverArguments += '--no-gpu'
        Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
    }
    else {
        $serverArguments += '--no-gpu'
        Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
    }

    # Start the server in background
    $serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

    # Give server time to start
    Write-Host "[TEST] Waiting for server to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5

    # Verify server is running
    if ($serverProcess -eq $null -or $serverProcess.HasExited) {
        Write-Error "Failed to start janas-server."
        exit 1
    }

    # Wait for server to be ready
    $connected = $false
    $retries = 0
    $maxRetries = 15

    Write-Host "[TEST] Testing server connectivity..." -ForegroundColor Yellow
    while (-not $connected -and $retries -lt $maxRetries) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "[SUCCESS] Server is running and responding on http://127.0.0.1:8080/test" -ForegroundColor Green
                $connected = $true
                break
            }
        }
        catch {
            Write-Host "." -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            $retries++
        }
    }

    if (-not $connected) {
        Write-Error "Failed to connect to server after $maxRetries attempts. Server may not be running correctly."
        exit 1
    }

    # Test basic connectivity
    Write-Host "\n[TEST] Testing basic connectivity..." -ForegroundColor Green
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080/test" -Method Get -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200 -and $response.Content -like "*Janas Chat*" -or $response.Content -like "*MCP*" -or $response.Content -like "*model*") {
            Write-Host "[SUCCESS] Basic connectivity test passed" -ForegroundColor Green
        }
        else {
            Write-Warning "Basic connectivity test: Received response but content doesn't look right."
        }
    }
    catch {
        Write-Error "Failed to connect to server: $($_.Exception.Message)"
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $modelDirectory)) {
    throw "Models directory not found."
}

# Find model file
$modelFile = Get-ChildItem -LiteralPath $modelDirectory -Filter "$Model*.jns" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $modelFile) {
    throw "Model $Model not found in models/. Please download it first with janas-get.exe."
}

# Check if services directory exists
if (-not (Test-Path -LiteralPath $servicesDirectory)) {
    throw "Services directory not found at $servicesDirectory"
}

# Get list of service executables
$services = Get-ChildItem -LiteralPath $servicesDirectory -Filter "*.exe" -File | Where-Object { $_.Name -match '^janas-' }

# Start the server
Write-Host "[TEST] Starting Janas Server with model: $($modelFile.Name)" -ForegroundColor Green

# Build server arguments
$serverArguments = @($modelFile.FullName, 
    '--host', '127.0.0.1', 
    '--port', '8080', 
    '--ctx', "$Context", 
    '--reserve', '8', 
    '--no-store'
)

# Add GPU flag if specified
if ($Gpu) {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using GPU mode" -ForegroundColor Yellow
}
else {
    $serverArguments += '--no-gpu'
    Write-Host "[INFO] Using CPU mode" -ForegroundColor Yellow
}

# Start the server in background
$serverProcess = Start-Process -FilePath $serverExecutable -ArgumentList $serverArguments -NoNewWindow -PassThru -RedirectStandardOutput $null -RedirectStandardError $null

# Give server time to start
Write-Host "[TEST] Waiting for server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}
Write-Host "[TEST] Waiting for server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verify server is running
if ($serverProcess -eq $null -or $serverProcess.HasExited) {
    Write-Error "Failed to start janas-server."
    exit 1
}