###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.1.0
#requires -Version 5.1
##########################################################################################

Remove-Module PsBundler -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\PsBundler.psm1" -Force
#Invoke-PsBundler -configPath "psbundler.config.testCycle.json" -verbose
Invoke-PsBundler -verbose