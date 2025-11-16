. "$PSScriptRoot/ui/alerts/alerts.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"
. "$PSScriptRoot/formConstants.ps1"


# ---------- Set process running state -------------------------
function Set-RunningState {
    param (
        [boolean]$val
    )

    $btnSearch = $script:GUI_CONTROLS.btnSearch
    $btnStop = $script:GUI_CONTROLS.btnStop
    $btnResume = $script:GUI_CONTROLS.btnResume
    $btnSaveSession = $script:GUI_CONTROLS.btnSaveSession
    $btnLoadSession = $script:GUI_CONTROLS.btnLoadSession
    $tabPageConfig = $script:GUI_CONTROLS.tabPageConfig

    $hasResumeData = $script:APP_CONTEXT.session.locationValue -and $script:APP_CONTEXT.session.locationType -and $script:APP_CONTEXT.session.filePath

    if ($hasResumeData) { $btnSearch.Left = $btnStop.Left - $FIELD_MARGIN_RIGHT - $btnResume.Width }
    else { $btnSearch.Left = $btnStop.Left }

    if ($val) { $btnStop.Text = "Stop Search" }
        
    $btnStop.Visible = $val
    $btnStop.Enabled = $val
    $btnSearch.Visible = (-not $val)
    $btnSearch.Enabled = (-not $val)
    $btnSaveSession.Enabled = (-not $val)
    $btnLoadSession.Enabled = (-not $val)
    $btnResume.Visible = (-not $val -and $hasResumeData)

    Set-ControlEnabledRecursive -container $tabPageConfig -state (-not $val) | Out-Null
}

function Get-EncodingsCheckBoxValues {
    param ([System.Windows.Forms.Form]$form)

    $chbEncodeWin1251 = Find-FormControl -container $form -name "chbEncodeWin1251"
    $chbEncodeWinUtf8 = Find-FormControl -container $form -name "chbEncodeWinUtf8"
    $chbEncodeWinUtf16 = Find-FormControl -container $form -name "chbEncodeWinUtf16"
    $chbEncodeWinKoi8 = Find-FormControl -container $form -name "chbEncodeWinKoi8"

    $result = ""
    if ($chbEncodeWin1251.Checked) { 
        if ($result.Length -ne 0) { $result += ", " }
        $result += "windows-1251"
    }
    if ($chbEncodeWinUtf8.Checked) { 
        if ($result.Length -ne 0) { $result += ", " }
        $result += "utf-8"
    }
    if ($chbEncodeWinUtf16.Checked) {
        if ($result.Length -ne 0) { $result += ", " }
        $result += "utf-16"
    }
    if ($chbEncodeWinKoi8.Checked) { 
        if ($result.Length -ne 0) { $result += ", " }
        $result += "koi8-r"
    }
    return $result
}

function Test-ShouldKeepResults {
    param(
        [boolean]$resume = $false
    )

    $grid = $script:GUI_CONTROLS.gridResults
    $tabControl = $script:GUI_CONTROLS.tabControl
    $tabPageResult = $script:GUI_CONTROLS.tabPageResult
    
    $tabControl.SelectedTab = $tabPageResult

    if ($resume) { return $true }

    if ($script:APP_CONTEXT.session.filePath) { 
        $result = [System.Windows.Forms.MessageBox]::Show(
            "There are uncompleted previous search. Do you want to clear it and start new search?",
            "Confirm",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )

        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        else {
            Clear-GridRows -grid $grid | Out-Null
            $script:APP_CONTEXT.totalFound = 0
            return $false
        }
    }

    if ((Get-FullRowsCount -grid $grid) -eq 0) { 
        $script:APP_CONTEXT.totalFound = 0
        return $false 
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "There are previous search results. Do you want to clear them?",
        "Confirm",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { 
        Clear-GridRows -grid $grid | Out-Null
        $script:APP_CONTEXT.totalFound = 0
        return $false
    }

    return $true
}

function Set-StatusTextValue {
    param([string]$msg)
        
    $txtStatusBar = $script:GUI_CONTROLS.txtStatusBar
    if ($txtStatusBar.Text -eq $msg) { return }
    $txtStatusBar.Text = $msg
} 

function Get-OnErrorHandler {
    return {
        param ([string]$msg)        
        Show-Error $msg
    } 
}

function Get-OnInfoHandler {
    return {
        param ([string]$msg)
        Show-Info $msg
    } 
}


function Set-SearchStartState {
    Set-RunningState -val $true | Out-Null
    $script:GUI_CONTROLS.txtStatusBar.Text = "Search started"
}

function Set-SearchStopState {
    param ([string]$msg)

    if ($script:APP_CONTEXT.state -eq "exit") { return }
    Set-RunningState -val $false | Out-Null

    $statusMsg = $msg
    if ($script:APP_CONTEXT.state -ne "stopped") { $statusMsg = "Search $($script:APP_CONTEXT.state)" }
    $script:GUI_CONTROLS.txtStatusBar.Text = $statusMsg
    Show-Info $msg
}
