function Initialize-ConsoleSearch {
    param (
        [hashtable]$params
    )

    Write-Host "$($script:APP_NAME) v$($script:APP_VERSION)"

    $params.onError = Get-OnErrorCoreHandler
    $params.onSearchStart = Get-OnSearchStartCoreHandler
    $params.onSearchStop = Get-OnSearchStopCoreHandler
    $params.addToResult = Get-AddToResultCoreHandler 
    $params.setStatusText = Get-SetStatusTextCoreHandler

    $err = Test-IsAllParamsValid -params $params
    if ($err) {
        &$params.onError $err
        return
    }

    $searchParams = Get-PreparedParams -params $params

    $err = Initialize-ResultSaveFile -searchParams $searchParams

    if ($err) {
        &$params.onError $err
        return
    }
    
    Invoke-SearchProcess -searchParams $searchParams | Out-Null
}