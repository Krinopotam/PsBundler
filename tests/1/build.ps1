 $Core = New-Module -Name 'Core' -ScriptBlock {
    function Write { param($msg) Write-Host "[CORE] $msg" }
    Export-ModuleMember -Function Write
}

$UI = New-Module -Name 'UI' -ScriptBlock {
    function Write { param($msg) Write-Host "[UI] $msg" }
    Export-ModuleMember -Function Write
}

# Вызов
&$Core.ExportedCommands['Write'] 'test from core'
&$UI.ExportedCommands['Write'] 'test from ui'

$module1 = Import-Module "$PSScriptRoot/module1.psm1" -PassThru
&$module1.ExportedCommands['Use-Func1'] -txt "test from module1"
Use-Func1 "!!!!!!!!!!!!!!"
