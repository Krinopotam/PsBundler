

function Use-Func1 {
    param (
        [string]$txt
    )
    Write-Host "Use-Func1: $txt"
}

Export-ModuleMember -Function Use-Func1