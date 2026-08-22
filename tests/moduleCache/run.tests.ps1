[CmdletBinding()]
param(
    [string]$PowerShellPath = (Get-Process -Id $PID).Path,
    [switch]$UsePowerShell2Runtime
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$configPath = Join-Path $PSScriptRoot 'psbundler.config.json'
$bundlerPath = Join-Path $repositoryRoot 'src\run.ps1'

function Invoke-TestProcess {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [switch]$PowerShell2
    )

    $hostArguments = @()
    if ($PowerShell2) { $hostArguments += @('-Version', '2') }

    & $PowerShellPath @hostArguments -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Test process failed with exit code ${LASTEXITCODE}: $ScriptPath"
    }
}

Invoke-TestProcess (Join-Path $PSScriptRoot 'diamond-main.ps1')
Invoke-TestProcess (Join-Path $PSScriptRoot 'force-main.ps1')
Invoke-TestProcess $bundlerPath @('-configPath', $configPath)
Invoke-TestProcess (Join-Path $PSScriptRoot 'build\module-cache-diamond.ps1') -PowerShell2:$UsePowerShell2Runtime
Invoke-TestProcess (Join-Path $PSScriptRoot 'build\module-cache-force.ps1') -PowerShell2:$UsePowerShell2Runtime
Invoke-TestProcess (Join-Path $PSScriptRoot 'build\module-cache-runspace-transfer.ps1') -PowerShell2:$UsePowerShell2Runtime

$runtimeVersion = if ($UsePowerShell2Runtime) { '2' } else { $PSVersionTable.PSVersion.ToString() }
Write-Host "Module cache integration tests passed with runtime PowerShell $runtimeVersion."
