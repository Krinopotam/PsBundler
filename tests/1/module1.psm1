

function Use-Func1 {
    param (
        [string]$txt
    )
    Write-Host "Use-Func1: $txt and script:var1 = @($script:var1)"
}

function Use-Func2 {
    param (
        [string]$txt
    )
    Write-Host "Use-Func2: $txt"
}

$var1="module var1"
$script:scriptVar1 = "Module ScriptVar1-"

#Export-ModuleMember -Function Use-Func1
#Export-ModuleMember -Variable var1