
param ($param1)

Import-Module "$PSScriptRoot\module2.psm1"

$var1 = "DDDDDDDDDDDDDDD"

function Use-Test {
    $mod = Get-ModuleName
    Write-Host "Use-Test instance 1 from $mod" + $var1
    module2\Use-Test2
}

function Get-ModuleName {
    "module1.psm1"
}

Export-ModuleMember -Function Use-Test -Variable var1