. "$PSScriptRoot/initTabConfig.ps1"
. "$PSScriptRoot/initTabResults.ps1"
. "$PSScriptRoot/formConstants.ps1"
. "$PSScriptRoot/formMethods.ps1"
. "$PSScriptRoot/runspace.ps1"
. "$PSScriptRoot/sessions.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"
. "$PSScriptRoot/../helpers/forms.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/../core/search.ps1" 
. "$PSScriptRoot/../core/searchPrepare.ps1" 
. "$PSScriptRoot/../core/validation.ps1"


$script:GUI_CONTROLS = [hashtable]::Synchronized(@{
        form               = $null
        tabControl         = $null
        tabPageConfig      = $null
        tabPagerResults    = $null
        gridResults        = $null
        gridSearchPatterns = $null
        gridLocations      = $null
        txtStatusBar       = $null
        btnSearch          = $null
        btnStop            = $null
        overlayPanel       = $null
    })

$script:GUI_CLOSE_TIMER = $null


function Initialize-Form {
    param (
        [hashTable]$baseParams
    )
    
    #region ---------- Initialize Form ------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $script:GUI_CONTROLS.form = $form
    $form.Name = "form"
    $form.Text = "$($script:APP_NAME) v.$($script:APP_VERSION)"
    $form.Width = 950
    $form.Height = 770
    $form.MinimumSize = '450,550'
    $form.StartPosition = "CenterScreen"
    
    $form.Add_FormClosing({
            if ($script:APP_CONTEXT.state -eq "exit" ) { 
                # already exiting
                $_.Cancel = $true
                return 
            } 

            if ($script:APP_CONTEXT.state -ne "running") { 
                if (-not $script:APP_CONTEXT.session.unsaved) {
                    Clear-RunSpace
                    return 
                }
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "You have unsaved session. Close application?",
                    "Confirm Exit",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) 

                if ($dialogResult -eq [System.Windows.Forms.DialogResult]::No) { $_.Cancel = $true } 
                return 
            } 

            $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                "Search is in progress. Cancel search and close application?",
                "Confirm Exit",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) 

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::No) {
                $_.Cancel = $true 
                return
            } 
             

            $script:APP_CONTEXT.state = "exit" 
            $_.Cancel = $true

                
            $script:GUI_CONTROLS.overlayPanel.Visible = $true

            $script:GUI_CONTROLS.btnStop.Enabled = $false
            $script:GUI_CONTROLS.btnStop.Text = "Stopping..."
            $script:GUI_CONTROLS.form.Enabled = $false

            $script:GUI_CLOSE_TIMER = New-Object System.Windows.Forms.Timer
            $script:GUI_CLOSE_TIMER.Interval = 200 
            $script:GUI_CLOSE_TIMER.Start()

            $script:GUI_CLOSE_TIMER.Add_Tick({
                    if ($script:RS_CONTEXT.ps.InvocationStateInfo.State -ne 'Running' -and $script:GUI_CLOSE_TIMER.Enabled) {
                        $script:GUI_CLOSE_TIMER.Stop()
                        $script:GUI_CONTROLS.btnStop.Text = "Stopped..."
                        Clear-RunSpace
                        $script:GUI_CONTROLS.form.Dispose()
                    }
                })
            
        })

    #endregion


    #region ---------- Initialize Tabs ------------------------------------
    $tabControl = New-Object System.Windows.Forms.TabControl
    $script:GUI_CONTROLS.tabControl = $tabControl
    $tabControl.Name = "tabControl"
    $tabControl.width = $form.ClientSize.Width
    $tabControl.Height = $form.ClientSize.Height - 80
    $tabControl.Location = "0,10"
    $tabControl.SizeMode = 'Fixed'
    $tabControl.Anchor = "Top, Bottom, Left, Right"
    $form.Controls.Add($tabControl)
    [void]$form.Handle # force creation to make form has real size
    [void]$tabControl.Handle # force creation to make tabControl has real size

    Initialize-TabConfig -baseParams $baseParams `
        -form $form `
        -tabControl $tabControl | Out-Null
        
    Initialize-TabResults -form $form -tabControl $tabControl | Out-Null

    #endregion
      
    #region ---------- Status Bar ----------------------------------------
    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusStrip.Name = "statusStrip"
    
    $txtStatusBar = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:GUI_CONTROLS.txtStatusBar = $txtStatusBar
    $txtStatusBar.Name = "txtStatusBar"
    $txtStatusBar.Text = "Ready" 
    $txtStatusBar.BackColor = [System.Drawing.Color]::LightGray
    $txtStatusBar.Spring = $true 
    $txtStatusBar.TextAlign = 'MiddleLeft'
    $statusStrip.Items.Add($txtStatusBar) | Out-Null
    $form.Controls.Add($statusStrip)
    
    #region ---------- Start Button --------------------------------------
    $btnSearch = New-Object System.Windows.Forms.Button
    $script:GUI_CONTROLS.btnSearch = $btnSearch
    $btnSearch.Name = "btnSearch"
    $btnSearch.Text = "Start new Search"
    $btnSearch.Top = $form.ClientSize.Height - 30 - $FORM_PADDING_BOTTOM - $txtStatusBar.Height
    $btnSearch.Left = $form.ClientSize.Width - 110 - $FORM_PADDING_RIGHT
    $btnSearch.Size = '110,30'
    $btnSearch.Anchor = "Right, Bottom"
    $btnSearch.Tag = $baseParams # WORKAROUND: PS has ugly closures, so we need to pass baseParams via Tag
    $btnSearch.Add_Click({ 
            param($s, $e)
            $params = $s.Tag
            $script:GUI_CONTROLS.txtStatusBar.Text = "Starting new search..."
            Start-GuiSearch -form $form -baseParams $params | Out-Null 
        })
    $form.Controls.Add($btnSearch)
    #endregion

    #region ---------- Stop Button --------------------------------------
    $btnStop = New-Object System.Windows.Forms.Button
    $script:GUI_CONTROLS.btnStop = $btnStop
    $btnStop.Name = "btnStop"
    $btnStop.Text = "Stop Search"
    $btnStop.Top = $btnSearch.Top
    $btnStop.Left = $btnSearch.Left
    $btnStop.Height = $btnSearch.Height
    $btnStop.Width = $btnSearch.Width
    $btnStop.Anchor = "Right, Bottom"
    $btnStop.Visible = $false
    $btnStop.Add_Click({ 
            $script:GUI_CONTROLS.btnStop.Enabled = $false
            $script:GUI_CONTROLS.btnStop.Text = "Stopping..."
            $script:APP_CONTEXT.state = "stopped" 
        })
    $form.Controls.Add($btnStop)
    #endregion

    #region ---------- Resume Button --------------------------------------
    $btnResume = New-Object System.Windows.Forms.Button
    $script:GUI_CONTROLS.btnResume = $btnResume
    $btnResume.Name = "btnResume"
    $btnResume.Text = "Resume Search"
    $btnResume.Top = $btnStop.Top
    $btnResume.Height = $btnStop.Height
    $btnResume.Width = $btnStop.Width
    $btnResume.Left = $btnStop.Left
    $btnResume.Anchor = "Right, Bottom"
    $btnResume.Visible = $false
    $btnResume.Tag = $baseParams # WORKAROUND: PS has ugly closures, so we need to pass baseParams via Tag
    $btnResume.Add_Click({ 
            param($s, $e)
            $params = $s.Tag
            $script:GUI_CONTROLS.txtStatusBar.Text = "Resuming search from $($script:APP_CONTEXT.session.filePath)"
            Start-GuiSearch -form $form -baseParams $params -resume $true | Out-Null 
        })
    $form.Controls.Add($btnResume)
    #endregion

    #region ---------- Save session Button --------------------------------------
    $btnSaveSession = New-Object System.Windows.Forms.Button
    $script:GUI_CONTROLS.btnSaveSession = $btnSaveSession
    $btnSaveSession.Name = "btnSaveSession"
    $btnSaveSession.Text = "Save session"
    $btnSaveSession.Top = $btnSearch.Top
    $btnSaveSession.Left = $FORM_PADDING_LEFT
    $btnSaveSession.Height = $btnSearch.Height
    $btnSaveSession.Width = 85
    $btnSaveSession.Anchor = "Left, Bottom"
    $btnSaveSession.Add_Click({ 
            Save-Session
        })
    $form.Controls.Add($btnSaveSession)
    #endregion

    #region ---------- Load session Button --------------------------------------
    $btnLoadSession = New-Object System.Windows.Forms.Button
    $script:GUI_CONTROLS.btnLoadSession = $btnLoadSession
    $btnLoadSession.Name = "btnLoadSession"
    $btnLoadSession.Text = "Load session"
    $btnLoadSession.Top = $btnSaveSession.Top
    $btnLoadSession.Left = $btnSaveSession.Right + $FIELD_MARGIN_RIGHT
    $btnLoadSession.Height = $btnSaveSession.Height
    $btnLoadSession.Width = 85
    $btnLoadSession.Anchor = "Left, Bottom"
    $btnLoadSession.Add_Click({ 
            if ($script:APP_CONTEXT.session.unsaved) {
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "You have unsaved session. Loading session will override your current session.`r`nDo you want to continue?",
                    "Confirm Exit",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) 

                if ($dialogResult -ne [System.Windows.Forms.DialogResult]::Yes) { return } 
            }

            Restore-Session
        })
    $form.Controls.Add($btnLoadSession)
    #endregion

    #region ---------- Overlay panel -------------------------------------
    $overlayPanel = New-Object Windows.Forms.Panel
    $script:GUI_CONTROLS.overlayPanel = $overlayPanel
    $overlayPanel.BackColor = [System.Drawing.Color]::DarkGray
    $overlayPanel.Dock = 'Fill'
    $overlayPanel.Visible = $false
    $form.Controls.Add($overlayPanel)
    $form.Controls.SetChildIndex($overlayPanel, 0)  

    $waitLabel = New-Object System.Windows.Forms.Label
    $waitLabel.Text = "Please wait, form is closing..."
    $waitLabel.ForeColor = [System.Drawing.Color]::White
    $waitLabel.Font = New-Object System.Drawing.Font($form.Font.FontFamily, 24, $form.Font.Style)
    $waitLabel.AutoSize = $true
    $waitLabel.Top = 50
    $waitLabel.Left = 50
    $overlayPanel.Controls.Add($waitLabel)
    #endregion 

    return $form
}

function Start-GuiSearch {
    param (
        [System.Windows.Forms.Form]$form,
        [hashTable]$baseParams,
        [boolean]$resume
    )

    $gridLocations = $script:GUI_CONTROLS.gridLocations
    $gridSearchPatterns = $script:GUI_CONTROLS.gridSearchPatterns
    $txtAllowedMasks = $script:GUI_CONTROLS.txtAllowedMasks
    $txtExcludedMasks = $script:GUI_CONTROLS.txtExcludedMasks
    $cbMaxFileSize = $script:GUI_CONTROLS.cbMaxFileSize
    $chbAutoSaveResults = $script:GUI_CONTROLS.chbAutoSaveResults
    $txtAutoSaveResults = $script:GUI_CONTROLS.txtAutoSaveResults
    $dpFileDateStart = $script:GUI_CONTROLS.dpFileDateStart
    $dpFileDateEnd = $script:GUI_CONTROLS.dpFileDateEnd

    $resultFilePath = ""
    if ($chbAutoSaveResults.Checked) {
        $resultFilePath = $txtAutoSaveResults.Text.Trim()
    }

    $params = @{}
    # copy baseParams
    foreach ($key in $baseParams.Keys) {
        $params[$key] = $baseParams[$key]
    }

    $params.appContext = $script:APP_CONTEXT
    $params.locations = Get-AdvancedGridDataHashtables -grid $gridLocations -filterColumn "Selected"
    $params.searchPatterns = Get-AdvancedGridDataHashtables -grid $gridSearchPatterns -filterColumn "Selected"
    $params.allowedMasks = [string]$txtAllowedMasks.Text
    $params.excludedMasks = [string]$txtExcludedMasks.Text
    $params.maxFileSize = [string]$cbMaxFileSize.Text
    $params.encodings = Get-EncodingsCheckBoxValues -form $form
    $params.resultFilePath = $resultFilePath
    $params.fileDateStart = $dpFileDateStart.Text
    $params.fileDateEnd = $dpFileDateEnd.Text
    $params.keepResults = $false
        
    $params.setStatusText = $null
    $params.onError = $null
    $params.onSearchStart = $null 
    $params.onSearchStop = $null
    $params.addToResult = $null

    $err = Test-IsAllParamsValid -params $params
    if ($err) {
        Show-Error $err
        return 
    }

    $searchParams = Get-PreparedParams -params $params

    $keepResults = Test-ShouldKeepResults -resume $resume
    if ($null -eq $keepResults ) { return }
    
    $searchParams.keepResults = $keepResults
        
    $err = Initialize-ResultSaveFile -searchParams $searchParams
    if ($err) {
        Show-Error $err
        return 
    }

    Set-RunningState -val $true | Out-Null
    Start-InRunspace -params $searchParams -resume $resume | Out-Null
}

