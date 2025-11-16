
. "$PSScriptRoot/../core/search.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/initGridResults.ps1"

$script:GUI_SYNC_TIMER = $null

$script:HashSync = [hashtable]::Synchronized(@{
        params            = $null
        setStatusText     = ""
        resultsQueue      = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
        hasError          = $null
        searchJustStarted = $false
        searchStopped     = $false
        isDebug           = $false
        resume            = $false
    })

function Start-InRunspace {
    param(
        [hashtable]$params,
        [boolean]$resume
    )

    Clear-RunSpace | Out-Null

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions = "ReuseThread"
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $script:RS_CONTEXT.ps = $ps
    $script:RS_CONTEXT.rs = $rs

    $functionsStrings = Get-FunctionsForRunspace

    $null = $ps.AddScript($functionsStrings).Invoke()
    $ps.Commands.Clear()

    $script:HashSync.params = $params
    $script:HashSync.setStatusText = ""
    $script:HashSync.resultsQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $script:HashSync.hasError = $null
    $script:HashSync.searchJustStarted = $false
    $script:HashSync.searchStopped = $false
    $script:HashSync.isDebug = Get-IsDebug
    $script:HashSync.resume = $resume

    $scriptBlockTxt = Get-RunspaceScriptBlockText
    $null = $ps.AddScript($scriptBlockTxt).AddArgument($script:HashSync) 

    $ps.BeginInvoke()

    $script:GUI_SYNC_TIMER = New-Object System.Windows.Forms.Timer
    $script:GUI_SYNC_TIMER.Interval = 200 
    $script:GUI_SYNC_TIMER.Start()

    $syncTimerHandler = Get-GuiSyncTimerHandler
    $script:GUI_SYNC_TIMER.Add_Tick($syncTimerHandler)
                
     
    <#     
    #$asyncResult = $ps.BeginInvoke()
    $ps.EndInvoke($asyncResult)
    if ($ps.Streams.Error.Count -gt 0) {
        foreach ($err in $ps.Streams.Error) {
            Add-Content -Path "log.txt" -Value "ERROR: $($err.ToString())"
        }
    }  #>

}

# Returns text of Get-RunspaceHandlerCode. We use scriptblock as text to avoid context mixing in the runspaces
function Get-RunspaceScriptBlockText {
    return (Get-Command -Name Get-RunspaceHandlerCode | Select-Object -ExpandProperty Definition)
}

function Get-RunspaceHandlerCode {
    param ([System.Collections.IDictionary]$context)
    
    $script:HashSync = $context

    if ( $script:HashSync.isDebug ) { $DebugPreference = 'Continue' }
    #$DebugPreference = 'Continue'

    Write-DebugLog "***************************** Start-InRunspace *****************************"
    try {
        Write-DebugLog "Runspace start"

        $searchParams = @{}
        foreach ($key in $script:HashSync.params.Keys) {
            $searchParams[$key] = $script:HashSync.params[$key]
        }

        $searchParams.setStatusText = {
            param([string]$text)
            $script:HashSync.setStatusText = $text
        } 
        $searchParams.addToResult = {
            param([System.Collections.Specialized.OrderedDictionary]$values)
            $script:HashSync.resultsQueue.Enqueue($values)
        }
        $searchParams.onError = {
            param([string]$err)
            $script:HashSync.hasError = $err
        } 
        $searchParams.onSearchStart = {
            $script:HashSync.searchJustStarted = $true
        } 
        $searchParams.onSearchStop = {
            param ([string]$msg)
            $script:HashSync.searchStopped = $msg
        }

        Invoke-SearchProcess -searchParams $searchParams -resume $script:HashSync.resume | Out-Null
        Write-DebugLog "Runspace end"
    }
    catch {
        Write-DebugErrorLog $_
    }
    finally {
        Write-DebugLog "----------------------------- Runspace finished ----------------------------"
    }

        
}
function Get-GuiSyncTimerHandler {
    return {
        if ($script:HashSync.searchJustStarted) { 
            $script:HashSync.searchJustStarted = $false
            Set-SearchStartState | Out-Null
        }

        if ($script:HashSync.setStatusText) { Set-StatusTextValue $script:HashSync.setStatusText | Out-Null }
                
        if (($script:HashSync.resultsQueue.Count) -gt 0) {
            while ($script:HashSync.resultsQueue.Count -gt 0) {
                $values = $script:HashSync.resultsQueue.Dequeue()
                Add-ToSearchResult -resultFilePath $script:HashSync.params.resultFilePath -values $values | Out-Null
            }
        }

        if ($script:HashSync.hasError) {
            $err = $script:HashSync.hasError
            $script:HashSync.hasError = $null
            $script:GUI_SYNC_TIMER.Stop()
            Show-Error $err
        }

        if ($script:HashSync.searchStopped -ne $false) {
            $script:GUI_SYNC_TIMER.Stop()
            $msg = $script:HashSync.searchStopped
            $script:HashSync.searchStopped = $false
            Set-SearchStopState -msg $msg | Out-Null
        }
    }
}

function Clear-RunSpace {
    if ($null -ne $script:RS_CONTEXT.ps) { 
        $script:RS_CONTEXT.ps.Dispose() 
        $script:RS_CONTEXT.ps = $null
    }

    if ($null -ne $script:RS_CONTEXT.rs) {
        $script:RS_CONTEXT.rs.Dispose()
        $script:RS_CONTEXT.rs = $null
    }
}

# Returns text of all functions in current session to pass it to runspace context
function Get-FunctionsForRunspace {
    $psVer = $PSVersionTable.PSVersion
    
    $commands = $null

    if ($psVer.Major -lt 3 ) { 
        #In PowerShell 2.0, it gets only commands in the current session
        $commands = Get-Command -CommandType Function | Where-Object { $_.Name -cmatch '^[A-Z][a-zA-Z0-9]+-[A-Z][a-zA-Z0-9]+$' -and $_.Name -ne "Get-Verb" } 
    }
    else {
        #Starting in PowerShell 3.0, by default, Get-Command gets all installed commands, so we need to specify -ListImported to get only commands from the current session
        $commands = Get-Command -ListImported -CommandType Function | Where-Object { $_.Name -cmatch '^[A-Z][a-zA-Z0-9]+-[A-Z][a-zA-Z0-9]+$' -and $_.Name -ne "Get-Verb" -and -not $_.Source } 
    }

    $result = @()
    foreach ($cmd in $commands) {
        $result += "function $($cmd.Name) {" + $cmd.Definition + "}"
    }

    return ($result -join "`n`n")
}