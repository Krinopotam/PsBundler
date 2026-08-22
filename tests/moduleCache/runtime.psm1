if ($null -eq $global:PsBundlerCacheRuntimeInitializations) {
    $global:PsBundlerCacheRuntimeInitializations = 0
}

$global:PsBundlerCacheRuntimeInitializations++
$script:PsBundlerCacheRuntimeInstanceId = [guid]::NewGuid().ToString('N')

function Get-PsBundlerCacheRuntimeInstanceId {
    $script:PsBundlerCacheRuntimeInstanceId
}

Export-ModuleMember -Function Get-PsBundlerCacheRuntimeInstanceId
