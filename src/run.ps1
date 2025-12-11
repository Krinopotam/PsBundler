###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.1.4
#requires -Version 5.1
##########################################################################################

Import-Module "$PSScriptRoot\PsBundler.psm1" -Force
Invoke-PsBundler -verbose

#Invoke-PsBundler  -configPath ".\posts\ps_imports\psbundler.config.json" -verbose

#Invoke-PsBundler -configPath ".\tests\cycled\psbundler.config.json" -verbose
#Invoke-PsBundler -configPath ".\tests\2\psbundler.config.json" -verbose
#Invoke-PsBundler -configPath ".\tests\3\psbundler.config.json" -verbose
#Invoke-PsBundler -configPath ".\tests\4\psbundler.config.json" -verbose