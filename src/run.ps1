Remove-Module PsBundler -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\PsBundler.psm1" -Force
#Invoke-PsBundler -configPath "psbundler.config.testCycle.json" -verbose
Invoke-PsBundler -verbose