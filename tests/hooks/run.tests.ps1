$ErrorActionPreference = "Stop"

$testRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $testRoot "..\..")).Path
$configPath = Join-Path $testRoot "psbundler.config.json"
$logPath = Join-Path $testRoot "hook-events.log"
$outputPath = Join-Path (Join-Path $testRoot "output") "hook-test.ps1"

if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
if (Test-Path -LiteralPath (Split-Path $outputPath -Parent)) {
    Remove-Item -LiteralPath (Split-Path $outputPath -Parent) -Recurse -Force
}

try {
    Import-Module (Join-Path $repoRoot "src\PsBundler.psd1") -Force
    Invoke-PSBundler -configPath $configPath

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Hook test bundle was not created"
    }

    $events = @(Get-Content -LiteralPath $logPath)
    if (($events -join ",") -ne "beforeBuild,afterBuild") {
        throw "Unexpected hook order: $($events -join ',')"
    }

    # A failing beforeBuild hook must prevent bundle generation.
    $failingConfigPath = Join-Path $testRoot "failing.config.json"
    $failingConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $failingConfig.hooks.beforeBuild = @("failing-before-build.ps1")
    $failingConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $failingConfigPath -Encoding UTF8
    Remove-Item -LiteralPath $outputPath -Force

    Invoke-PSBundler -configPath $failingConfigPath
    if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        throw "Bundle was created after a failing beforeBuild hook"
    }

    $events = @(Get-Content -LiteralPath $logPath)
    if ($events[-1] -ne "afterBuildOnFailure") {
        throw "afterBuild hook did not run after a failed build"
    }
}
finally {
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
    if (Test-Path -LiteralPath (Split-Path $outputPath -Parent)) {
        Remove-Item -LiteralPath (Split-Path $outputPath -Parent) -Recurse -Force
    }
    $failingConfigPath = Join-Path $testRoot "failing.config.json"
    if (Test-Path -LiteralPath $failingConfigPath) { Remove-Item -LiteralPath $failingConfigPath -Force }
}

Write-Host "Hook tests passed." -ForegroundColor Green
