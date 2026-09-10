$logPath = Join-Path $PSScriptRoot "hook-events.log"
Add-Content -LiteralPath $logPath -Value "beforeBuild"
