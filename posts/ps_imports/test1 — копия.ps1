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


$global:__MODULES_d01ad524f4c444128a416d123ece0676 = @{}


$global:__MODULES_d01ad524f4c444128a416d123ece0676["f32fa61834c043e49a73e56ccf0fddbc"] = {
    
    function Use-Test {
        $mod = Get-ModuleName
        Write-Host "Use-Test instance 2 from $mod"
    }
    
    function Get-ModuleName {
        "module2.psm1"
    }
    
    function Use-Test2 {
        Write-Host "Use-Test2 from module2.psm1"
    }

    Export-ModuleMember -Function Use-Test, Use-Test2
}

$global:__MODULES_d01ad524f4c444128a416d123ece0676["bf51d8fd00754b59aabbc15d2260767d"] = {
    
    
    & {Import-Module (& { $mod = New-Object System.Management.Automation.PSModuleInfo($__MODULES_d01ad524f4c444128a416d123ece0676["f32fa61834c043e49a73e56ccf0fddbc"])
        $flags  = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $setName = [System.Management.Automation.PSModuleInfo].GetMethod("SetName", $flags)
        $setName.Invoke($mod, @("module2")) | Out-Null
        $mod }) -Scope Local -Force -DisableNameChecking }
    
    $script:var1 = "DDDDDDDDDDDDDDD"
    
    function Use-Test {
        $mod = Get-ModuleName
        Write-Host "Use-Test instance 1 from $mod" + $script:var1
        module2\Use-Test2
    }
    
    function Get-ModuleName {
        "module1.psm1"
    }
    
    Export-ModuleMember -Function Use-Test -Variable var1
}

& {Import-Module (& { $mod = New-Object System.Management.Automation.PSModuleInfo($__MODULES_d01ad524f4c444128a416d123ece0676["bf51d8fd00754b59aabbc15d2260767d"])
    $flags  = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $setName = [System.Management.Automation.PSModuleInfo].GetMethod("SetName", $flags)
    $setName.Invoke($mod, @("module1")) | Out-Null
    $mod }) -Scope Local -Force -DisableNameChecking}
& {Import-Module (& { $mod = New-Object System.Management.Automation.PSModuleInfo($__MODULES_d01ad524f4c444128a416d123ece0676["f32fa61834c043e49a73e56ccf0fddbc"])
    $flags  = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $setName = [System.Management.Automation.PSModuleInfo].GetMethod("SetName", $flags)
    $setName.Invoke($mod, @("module2")) | Out-Null
    $mod }) -Scope Local -Force -DisableNameChecking}

Get-Command Use-Test -All


module1\Use-Test
module2\Use-Test


 
