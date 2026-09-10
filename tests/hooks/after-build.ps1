$logPath = Join-Path $PSScriptRoot "hook-events.log"
$bundlePath = Join-Path (Join-Path $PSScriptRoot "output") "hook-test.ps1"
if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
    Add-Content -LiteralPath $logPath -Value "afterBuild"
}
else {
    Add-Content -LiteralPath $logPath -Value "afterBuildOnFailure"
}
