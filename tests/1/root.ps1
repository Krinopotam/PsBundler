#using module .\module1.psm1
using namespace System.Management.Automation.Language

#& $PSScriptRoot\module2.ps1
$sb2 = {
    $fooVal = $ExecutionContext.SessionState.PSVariable.GetValue('foo')
    function Use-Module2{
        "Using Module2"
    }

    Write-Host "Module2: $fooVal"
}


$sb = {
    param (        [string] $extraVal    )
    $sb2 = $ExecutionContext.SessionState.PSVariable.GetValue('sb2')
    Import-Module (New-Module -ScriptBlock $sb2) -DisableNameChecking 

    $fooVal = $ExecutionContext.SessionState.PSVariable.GetValue('foo')

    function Private-Func {
        "I am private"
        Use-Module2
    }

    function Public-Func {
        "I am public"
        Private-Func
    }

    Write-Host $extraVal
    Write-Host $fooVal
    #Export-ModuleMember -Function Public-Func
}
$foo = "---script:foo---"

$internalModule = New-Module -ScriptBlock $sb -ArgumentList "extraVal"

# Импортируем модуль в текущую сессию
Import-Module $internalModule -DisableNameChecking 

Public-Func "111"
