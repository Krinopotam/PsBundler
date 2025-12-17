<# $mod1 = & { Import-Module "$PSScriptRoot\import1.psm1" -Force -PassThru } 
$mod2 = & { Import-Module "$PSScriptRoot\import2.psm1" -Force -PassThru }

#&$mod1.ExportedCommands['Test-Func1'] -txt "test from module1"
Test-Func1 

$mod1.Invoke({ Test-Func1 })
& $mod1.ExportedFunctions['Test-Func1'] #>

#----------
<# function Import-IsolatedModule {
    param([string]$Path)

    (New-Module -AsCustomObject -ScriptBlock {
        param($Path)
        $script:Module = Import-Module $Path -Force -PassThru
        Export-ModuleMember -Variable Module
    } -ArgumentList $Path).Module
}

$mod1 = Import-IsolatedModule "$PSScriptRoot\module1.psm1"
$mod2 = Import-IsolatedModule "$PSScriptRoot\module2.psm1"
$mod1.Invoke({ Use-Test })
$mod2.Invoke({ Use-Test }) #>
#
#Use-Test


#$mod1 = Import-Module "$PSScriptRoot\module1.psm1" -AsCustomObject
#$mod2 = Import-Module "$PSScriptRoot\module2.psm1" -AsCustomObject

#$mod1."Use-Test"()
#module2\Use-Test

#Use-Test2


<# Import-Module "$PSScriptRoot\module1.psm1"
Import-Module "$PSScriptRoot\module2.psm1"

. {
    function Use-Test {
        Write-Host "Use-Test from script-block"
    }

    Get-Command Use-test -All
}


Use-Test

Get-Command Use-test -All
 #>

#$obj = New-Module -ScriptBlock {function F {"Hello"}} 


<# 
$scriptBlock = {
    function Get-MyGreeting {
        Write-Host "Hello from dynamic PSModuleInfo!"
    }
    Export-ModuleMember -Function Get-MyGreeting
}
$moduleInfoFromScriptBlock = New-Object System.Management.Automation.PSModuleInfo($scriptBlock)
& { Import-Module $moduleInfoFromScriptBlock -Scope Local } #>


#& {Import-Module "$PSScriptRoot\module1.psm1"}
#& {Import-Module "$PSScriptRoot\module2.psm1"}
Using Module ".\module1.psm1"
#Using Module ".\module2.psm1"

Get-Command Use-Test -All

Get-ModuleName

# $mod1.Invoke({ Use-Test })
# $mod2.Invoke({ Use-Test })
#module1\Use-Test
#module2\Use-Test

#Show-AstViewer

 