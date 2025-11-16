using module .\module1.psm1
using namespace System.Management.Automation.Language

& $PSScriptRoot\module2.ps1


$internalModule = New-Module -ScriptBlock {
    
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $path = "",

        [Ast]$ast
        
    )
    function Private-Func {
        "I am private"
    }

    function Public-Func {
        "I am public"
        Private-Func
    }

    #Export-ModuleMember -Function Public-Func
	$var1 = "1111111"
}

# Импортируем модуль в текущую сессию
Import-Module $internalModule -DisableNameChecking


$script:var1="22222"
Use-Func1 "111"

$Script:scriptVar1

$x=2

function RootFunc {
    "I am Root func"
}

$sb = {
    $x2=1

    $sb2 = {
        $x2=2
        function MyPrivate {
            "I am MyPrivate"
        }

        RootFunc
    }

    . $sb2

    Write-Host "============= $x2"
}

. $sb

Write-Host "-------------- $x"
MyPrivate
