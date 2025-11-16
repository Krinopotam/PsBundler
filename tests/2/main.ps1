###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.1.0
#requires -Version 5.1
##########################################################################################

Remove-Module PsBundler -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\module1.psm1" -Force
#Invoke-PsBundler -configPath "psbundler.config.testCycle.json" -verbose
Use-Test1 -verbose