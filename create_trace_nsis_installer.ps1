<#
.SYNOPSIS
    Simplified script to create Trace NSIS installers with optional clean rebuild.

.DESCRIPTION
    This script automates the process of building and packaging Trace NSIS installers.
    Supports clean rebuild with -Rebuild flag and lite/full package options.

.PARAMETER Rebuild
    Performs a clean rebuild by removing existing build artifacts before building.

.PARAMETER Lite
    Creates a lite installer without libraries.

.PARAMETER Full
    Creates a full installer with all libraries (default behavior).

.PARAMETER Diagnostic
    Creates a diagnostic installer with release performance and debug logging enabled.

.PARAMETER TraceWinBuilderPath
    Path to the trace-win-builder directory. Defaults to <ScriptRoot>\trace-win-builder.

.PARAMETER TraceSourcePath
    Path to the Trace source directory. Defaults to <ScriptRoot>\Trace.

.EXAMPLE
    .\create_trace_nsis_installer.ps1 -Rebuild -Lite
    Cleans build directories, rebuilds, and creates a lite installer.

.EXAMPLE
    .\create_trace_nsis_installer.ps1 -Rebuild -Full
    Cleans build directories, rebuilds, and creates a full installer.

.EXAMPLE
    .\create_trace_nsis_installer.ps1 -Lite
    Creates a lite installer without cleaning/rebuilding.

.EXAMPLE
    .\create_trace_nsis_installer.ps1 -Rebuild -Full -Diagnostic
    Creates a diagnostic installer with full libraries and debug logging.
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$Rebuild,

    [Parameter(Mandatory=$false)]
    [switch]$Lite,

    [Parameter(Mandatory=$false)]
    [switch]$Full,

    [Parameter(Mandatory=$false)]
    [switch]$Diagnostic,

    [Parameter(Mandatory=$false)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",

    [Parameter(Mandatory=$false)]
    [string]$TraceWinBuilderPath = (Join-Path $PSScriptRoot "trace-win-builder"),

    [Parameter(Mandatory=$false)]
    [string]$TraceSourcePath = (Join-Path $PSScriptRoot "Trace")
)

# Set strict error handling
$ErrorActionPreference = "Stop"

# Resolve to absolute paths so relative paths (e.g. ..\Trace) stay valid if cwd changes
$script:TraceWinBuilderPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TraceWinBuilderPath)
$script:TraceSourcePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TraceSourcePath)
$script:Arch = $Arch

# Load .env file from trace-win-builder if it exists
$envFile = Join-Path $script:TraceWinBuilderPath ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
        }
    }
    Write-Host "Loaded environment from .env" -ForegroundColor DarkGray
}

# Configuration based on build type
if ($Diagnostic) {
    $script:BuildType = "RelWithDebInfo"
    $script:BuildConfigName = "trace-diagnostic"
    Write-Host "Building DIAGNOSTIC version (Release performance + debug logging)" -ForegroundColor Magenta
} else {
    $script:BuildType = "Release"
    $script:BuildConfigName = "trace-nightly"
}

# Derived paths
$script:BuildName = "$script:Arch-windows-$script:BuildType"
$script:BuildPath = "$script:TraceSourcePath\build\$script:BuildName"

# Track location stack depth for proper cleanup
$script:LocationStackDepth = 0

# Validate critical paths exist
if (-not (Test-Path $script:TraceWinBuilderPath)) {
    Write-Error "Trace win-builder directory not found: $script:TraceWinBuilderPath"
    Write-Error "Please verify the path is correct."
    exit 1
}

if (-not (Test-Path $script:TraceSourcePath)) {
    Write-Error "Trace source directory not found: $script:TraceSourcePath"
    Write-Error "Please verify the path is correct."
    exit 1
}

# Validate parameters
if ($Lite -and $Full) {
    Write-Error "Cannot specify both -Lite and -Full flags. Choose one."
    exit 1
}

# Default to Full if neither is specified
if (-not $Lite -and -not $Full) {
    Write-Host "No package type specified, defaulting to Full" -ForegroundColor Yellow
    $Full = $true
}

# Function to check if directory exists and remove it
function Remove-IfExists {
    param([string]$Path)
    
    if (Test-Path $Path) {
        Write-Host "Removing: $Path" -ForegroundColor Yellow
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not fully remove $Path : $_"
        }
    } else {
        Write-Host "Path does not exist, skipping: $Path" -ForegroundColor Gray
    }
}

# Function to safely push location and track depth
function Enter-BuildDirectory {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Build directory does not exist: $Path"
    }
    
    Push-Location $Path
    $script:LocationStackDepth++
    Write-Host "Working directory: $Path" -ForegroundColor DarkGray
}

# Function to safely pop location
function Exit-BuildDirectory {
    if ($script:LocationStackDepth -gt 0) {
        Pop-Location
        $script:LocationStackDepth--
    }
}

# Function to restore all pushed locations (for error cleanup)
function Restore-AllLocations {
    while ($script:LocationStackDepth -gt 0) {
        Pop-Location
        $script:LocationStackDepth--
    }
}

# Function to invoke build.ps1 and check for errors properly
function Invoke-BuildStep {
    param(
        [string]$StepName,
        [scriptblock]$ScriptBlock
    )
    
    Write-Host "`n$StepName..." -ForegroundColor Cyan
    
    # Temporarily allow commands to complete even if they write to stderr
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    
    # Clear any previous exit code by running a successful command
    $null = cmd /c "exit 0"
    
    # Execute the script block
    & $ScriptBlock
    
    # Capture the exit code immediately after execution
    # If LASTEXITCODE is null, treat it as success (0)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    
    # Restore error action preference
    $ErrorActionPreference = $previousErrorActionPreference
    
    # Only check LASTEXITCODE (not $?) because build tools often write to stderr even on success
    # CMake, in particular, writes configuration info to stderr which makes $? return false
    if ($exitCode -ne 0) {
        throw "$StepName failed with exit code $exitCode"
    }
    
    Write-Host "$StepName completed successfully" -ForegroundColor Green
}

# Step 1: Clean rebuild if requested
if ($Rebuild) {
    Write-Host "`n=== Starting Clean Rebuild ===" -ForegroundColor Cyan
    
    try {
        # Remove .out directory (packaged output)
        Remove-IfExists "$script:TraceWinBuilderPath\.out"
        
        # Remove .build directory (library builds cache)
        Remove-IfExists "$script:TraceWinBuilderPath\.build"
        
        # Remove main build directory
        Remove-IfExists $script:BuildPath
        
        # Change to win-builder directory
        Enter-BuildDirectory $script:TraceWinBuilderPath
        
        # Initialize build environment
        Invoke-BuildStep "Initializing build environment" {
            .\build.ps1 -Init
        }
        
        # Build Trace
        Invoke-BuildStep "Building Trace" {
            .\build.ps1 -Build -Arch $script:Arch -BuildType $script:BuildType -BuildConfigName $script:BuildConfigName
        }
        
        Exit-BuildDirectory
        Write-Host "`n=== Clean Rebuild Complete ===" -ForegroundColor Green
    }
    catch {
        Write-Error "Clean rebuild failed: $_"
        Restore-AllLocations
        exit 1
    }
}

# Verify build exists before packaging (if not rebuilding)
if (-not $Rebuild) {
    if (-not (Test-Path $script:BuildPath)) {
        Write-Error "Build directory does not exist: $script:BuildPath"
        Write-Error "Run with -Rebuild flag to perform a clean build first."
        exit 1
    }
    Write-Host "Using existing build at: $script:BuildPath" -ForegroundColor Gray
}

# Step 2: Prepare and Package
try {
    Enter-BuildDirectory $script:TraceWinBuilderPath

    if ($Lite) {
        Write-Host "`n=== Creating Lite Installer ===" -ForegroundColor Cyan
        
        # Prepare lite package
        Invoke-BuildStep "Preparing lite package" {
            .\build.ps1 -PreparePackage -Arch $script:Arch -BuildType $script:BuildType -BuildConfigName $script:BuildConfigName -Lite
        }
        
        # Package lite installer
        Invoke-BuildStep "Packaging lite installer" {
            .\build.ps1 -Package -PackType nsis -Arch $script:Arch -BuildType $script:BuildType -BuildConfigName $script:BuildConfigName -Lite
        }
        
        Write-Host "`n=== Lite Installer Created Successfully ===" -ForegroundColor Green
    }

    if ($Full) {
        Write-Host "`n=== Creating Full Installer ===" -ForegroundColor Cyan
        
        # Prepare full package
        Invoke-BuildStep "Preparing full package" {
            .\build.ps1 -PreparePackage -Arch $script:Arch -BuildType $script:BuildType -BuildConfigName $script:BuildConfigName
        }
        
        # Package full installer
        Invoke-BuildStep "Packaging full installer" {
            .\build.ps1 -Package -PackType nsis -Arch $script:Arch -BuildType $script:BuildType -BuildConfigName $script:BuildConfigName
        }
        
        Write-Host "`n=== Full Installer Created Successfully ===" -ForegroundColor Green
    }

    Exit-BuildDirectory
}
catch {
    Write-Error "Packaging failed: $_"
    Restore-AllLocations
    exit 1
}

# Display output location and verify results
$OutputPath = "$script:TraceWinBuilderPath\.out"
if (Test-Path $OutputPath) {
    Write-Host "`nInstaller location: $OutputPath" -ForegroundColor Cyan
    
    # List the installer files (force array to handle single file case)
    $InstallerFiles = @(Get-ChildItem $OutputPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue)
    if ($InstallerFiles.Count -gt 0) {
        Write-Host "`nGenerated installers:" -ForegroundColor Cyan
        foreach ($file in $InstallerFiles) {
            Write-Host "  - $($file.Name) ($([math]::Round($file.Length / 1MB, 2)) MB)" -ForegroundColor White
        }
    } else {
        Write-Warning "No installer files (.exe) found in output directory!"
        Write-Warning "The build may have failed silently. Check the output above for errors."
    }
} else {
    Write-Warning "Output directory does not exist: $OutputPath"
    Write-Warning "The build may have failed. Check the output above for errors."
}

Write-Host "`n=== All Done! ===" -ForegroundColor Green
