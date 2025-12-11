
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