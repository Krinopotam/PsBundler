############################## Core handlers ##############################

function Get-SetStatusTextCoreHandler {
    return {
        param([string]$msg)
        Write-Verbose $msg
    } 
}

function Get-OnErrorCoreHandler {
    return {
        param ([string]$msg)
        Write-Host "Error: $msg" -ForegroundColor Red
    } 
}

function Get-OnInfoCoreHandler {
    return {
        param ([string]$msg)
        Write-Host $msg -ForegroundColor Cyan
    } 
}


function Get-OnSearchStartCoreHandler {
    return {
        Write-Host "Search started"
    } 
}

function Get-OnSearchStopCoreHandler {
    return {
        param ([string]$msg)
        if ($script:APP_CONTEXT.state -eq "exit") { return }
        Write-Host $msg
    } 
}

function Get-AddToResultCoreHandler {
    return {
        param(
            [hashtable]$searchParams,
            [System.Collections.Specialized.OrderedDictionary]$values
        )

        $script:APP_CONTEXT.totalFound++
        $values["#"] = $script:APP_CONTEXT.totalFound

        Write-Host "Found: $($script:APP_CONTEXT.totalFound). $($values.FilePath) => $($values.Content)`r`n"

        if (-not $searchParams.resultFilePath) { return }

        Add-ValueToResultFile -savePath $searchParams.resultFilePath -values $values
    } 
}
