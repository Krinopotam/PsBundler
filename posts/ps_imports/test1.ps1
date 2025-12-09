<# $mod1 = & { Import-Module "$PSScriptRoot\import1.psm1" -Force -PassThru } 
$mod2 = & { Import-Module "$PSScriptRoot\import2.psm1" -Force -PassThru }

#&$mod1.ExportedCommands['Test-Func1'] -txt "test from module1"
Test-Func1 

$mod1.Invoke({ Test-Func1 })
& $mod1.ExportedFunctions['Test-Func1'] #>


function Import-IsolatedModule {
    param([string]$Path)

    (New-Module -AsCustomObject -ScriptBlock {
        param($Path)
        $script:Module = Import-Module $Path -Force -PassThru
        Export-ModuleMember -Variable Module
    } -ArgumentList $Path).Module
}

$mod1 = Import-IsolatedModule "$PSScriptRoot\import1.psm1"
$mod2 = Import-IsolatedModule "$PSScriptRoot\import2.psm1"
$mod1.Invoke({ Test-Func1 })
$mod2.Invoke({ Test-Func1 })

#Test-Func1