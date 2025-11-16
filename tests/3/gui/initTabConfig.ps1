. "$PSScriptRoot/formConstants.ps1"
. "$PSScriptRoot/initGridLocations.ps1"
. "$PSScriptRoot/initGridSearchPatterns.ps1"
. "$PSScriptRoot/ui/datePicker/datePicker.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"

function Initialize-TabConfig {
    param (
        [hashTable]$baseParams,
        [System.Windows.Forms.Form]$form,
        [System.Windows.Forms.TabControl]$tabControl
    )

    $tabPageConfig = New-Object System.Windows.Forms.TabPage
    $script:GUI_CONTROLS.tabPageConfig = $tabPageConfig
    $tabPageConfig.Name = "tabPageConfig"
    $tabPageConfig.Text = 'Config'
    $tabControl.TabPages.Add($tabPageConfig)
    [void]$tabPageConfig.Handle # force creation to make tabPageConfig has real size

    $tabInnerWidth = $tabPageConfig.ClientSize.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT


    #region ---------- Split Container -----------------------------------
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Name = "splitContainer"
    $splitContainer.Dock = 'Fill'
    $splitContainer.Orientation = 'Horizontal' 

    $tabPageConfig.Controls.Add($splitContainer)

    $panel1 = New-Object System.Windows.Forms.Panel
    $panel1.Name = "panel1"
    $panel1.Dock = 'Fill'
    #$panel1.BackColor = 'LightBlue'
    $splitContainer.Panel1.Controls.Add($panel1)

    $panel2 = New-Object System.Windows.Forms.Panel
    $panel2.Name = "panel2"
    $panel2.Dock = 'Fill'
    #$panel2.BackColor = 'LightGreen'
    $splitContainer.Panel2.Controls.Add($panel2)


    [void]$splitContainer.Handle
    [void]$panel1.Handle 
    [void]$panel2.Handle 

    $splitContainer.SplitterDistance = 150
    #endregion


    #region ---------- Locations grid ------------------------------------
    Initialize-GridLocations -form $form -container $panel1 | Out-Null
    #endregion

    #region ---------- Search patterns grid ------------------------------
    $gridSearchPatterns = Initialize-GridSearchPatterns -form $form -container $panel2 
    #endregion

    $gbContentSearchParams = New-Object System.Windows.Forms.GroupBox
    $gbContentSearchParams.Name = "gbContentSearchParams"
    $gbContentSearchParams.Text = "Content search parameters"
    $gbContentSearchParams.Top = $gridSearchPatterns.Bottom + $FIELD_MARGIN_BOTTOM
    $gbContentSearchParams.Left = $FORM_PADDING_LEFT
    $gbContentSearchParams.Width = $tabInnerWidth
    $gbContentSearchParams.Height = 150
    $gbContentSearchParams.Anchor = "Bottom, Left, Right"
    $panel2.Controls.Add($gbContentSearchParams)
    $groupInnerWidth = $gbContentSearchParams.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT
    $ttpgbContentSearchParams = New-Object System.Windows.Forms.ToolTip
    $ttpgbContentSearchParams.SetToolTip($gbContentSearchParams, "Applies to content search only. Ignored for file name search")
    $ttpgbContentSearchParams.IsBalloon = $true

    #region ---------- Extensions ----------------------------------------
    $lblAllowedMasks = New-Object System.Windows.Forms.Label
    $lblAllowedMasks.Name = "lblAllowedMasks"
    $lblAllowedMasks.Top = $FORM_PADDING_TOP
    $lblAllowedMasks.Text = "File masks for content search: (*.txt,*.log,...):"
    $lblAllowedMasks.Left = $FORM_PADDING_LEFT
    $lblAllowedMasks.Height = $LABEL_HEIGHT
    $lblAllowedMasks.Width = $groupInnerWidth
    $lblAllowedMasks.AutoEllipsis = $true
    $lblAllowedMasks.Anchor = "Bottom, Left, Right"
    $gbContentSearchParams.Controls.Add($lblAllowedMasks)
    $ttpAllowedMasks = New-Object System.Windows.Forms.ToolTip
    $ttpAllowedMasks.SetToolTip($lblAllowedMasks, "Content search will be applied to files with these masks. Empty or '*.*' means all files. For no extension use '*.'")
    $ttpAllowedMasks.IsBalloon = $true


    $txtAllowedMasks = New-Object System.Windows.Forms.TextBox
    $script:GUI_CONTROLS.txtAllowedMasks = $txtAllowedMasks
    $txtAllowedMasks.Name = "txtAllowedMasks"
    $txtAllowedMasks.Left = $FORM_PADDING_LEFT
    $txtAllowedMasks.Top = $lblAllowedMasks.Bottom
    $txtAllowedMasks.Height = $FIELD_HEIGHT
    $txtAllowedMasks.Width = $groupInnerWidth
    $txtAllowedMasks.Font = New-Object System.Drawing.Font("Courier New", 9)
    $txtAllowedMasks.Anchor = "Bottom, Left, Right"
    $gbContentSearchParams.Controls.Add($txtAllowedMasks)
    #endregion

    #region ---------- Excluded file masks -------------------------------
    $lblExcludedMasks = New-Object System.Windows.Forms.Label
    $lblExcludedMasks.Name = "lblExcludedMasks"
    $lblExcludedMasks.Text = "Excluded files masks (*.txt,*.log,...)"
    $lblExcludedMasks.Top = $txtAllowedMasks.Bottom + $FIELD_MARGIN_BOTTOM
    $lblExcludedMasks.Left = $FORM_PADDING_LEFT
    $lblExcludedMasks.Height = $LABEL_HEIGHT
    $lblExcludedMasks.Width = $groupInnerWidth - 100 - $FIELD_MARGIN_RIGHT
    $lblExcludedMasks.Anchor = "Bottom, Left, Right"
    $lblExcludedMasks.AutoEllipsis = $true
    $gbContentSearchParams.Controls.Add($lblExcludedMasks)
    $ttpExcludedMasks = New-Object System.Windows.Forms.ToolTip
    $ttpExcludedMasks.SetToolTip($lblExcludedMasks, "File with these masks will be excluded from content search. Empty means no excluded files.")
    $ttpExcludedMasks.IsBalloon = $true

    $txtExcludedMasks = New-Object System.Windows.Forms.TextBox
    $script:GUI_CONTROLS.txtExcludedMasks = $txtExcludedMasks
    $txtExcludedMasks.Name = "txtExcludedMasks"
    $txtExcludedMasks.Top = $lblExcludedMasks.Bottom
    $txtExcludedMasks.Left = $FORM_PADDING_LEFT
    $txtExcludedMasks.Height = $FIELD_HEIGHT
    $txtExcludedMasks.Width = $groupInnerWidth - 100 - $FIELD_MARGIN_RIGHT
    $txtExcludedMasks.Font = New-Object System.Drawing.Font("Courier New", 9)
    $txtExcludedMasks.Anchor = "Bottom, Left, Right"
    $gbContentSearchParams.Controls.Add($txtExcludedMasks)
    #endregion
    
    #region ---------- Max file size -------------------------------------
    $lblMaxFileSize = New-Object System.Windows.Forms.Label
    $lblMaxFileSize.Name = "lblMaxFileSize"
    $lblMaxFileSize.Text = "Max file size:"
    $lblMaxFileSize.Top = $lblExcludedMasks.Top
    $lblMaxFileSize.Left = $lblExcludedMasks.Right + $FIELD_MARGIN_RIGHT
    $lblMaxFileSize.Height = $LABEL_HEIGHT
    $lblMaxFileSize.Width = 100
    $lblMaxFileSize.Anchor = "Bottom, Right"
    $lblMaxFileSize.AutoEllipsis = $true
    $gbContentSearchParams.Controls.Add($lblMaxFileSize)
    $ttpMaxFileSize = New-Object System.Windows.Forms.ToolTip
    $ttpMaxFileSize.SetToolTip($lblMaxFileSize, "Max file size for content search. 0 or empty means no limit. Can use Kb, Mb, Gb or just bytes.")
    $ttpMaxFileSize.IsBalloon = $true

    $cbMaxFileSize = New-Object System.Windows.Forms.ComboBox
    $script:GUI_CONTROLS.cbMaxFileSize = $cbMaxFileSize
    $cbMaxFileSize.Name = "cbMaxFileSize"
    $cbMaxFileSize.DropDownStyle = 'DropDown'
    $cbMaxFileSize.Top = $txtExcludedMasks.Top
    $cbMaxFileSize.Left = $txtExcludedMasks.Right + $FIELD_MARGIN_RIGHT
    $cbMaxFileSize.Height = $FIELD_HEIGHT
    $cbMaxFileSize.Width = 100
    $cbMaxFileSize.Items.AddRange(@("1Kb", "5Kb", "10Kb", "50Kb", "100Kb", "500Kb", "1Mb", "3Mb", "5Mb", "10Mb", "50Mb", "100Mb", "500Mb", "1Gb"))
    $cbMaxFileSize.Anchor = "Bottom, Right"
    $gbContentSearchParams.Controls.Add($cbMaxFileSize)
    #endregion

    #region Encodings
    $lblEncodings = New-Object System.Windows.Forms.Label
    $lblEncodings.Name = "lblEncodings"
    $lblEncodings.Text = "Encodings:"
    $lblEncodings.Top = $txtExcludedMasks.Bottom + $FIELD_MARGIN_BOTTOM
    $lblEncodings.Left = $FORM_PADDING_LEFT
    $lblEncodings.Height = $LABEL_HEIGHT
    $lblEncodings.Width = 70
    $lblEncodings.Anchor = "Bottom, Left"
    $lblEncodings.AutoEllipsis = $true
    $gbContentSearchParams.Controls.Add($lblEncodings)
    $ttpExcludedMasks = New-Object System.Windows.Forms.ToolTip
    $ttpExcludedMasks.SetToolTip($lblEncodings, "Select encodings for content search (each adds ~50% to search time)")
    $ttpExcludedMasks.IsBalloon = $true

    $chbEncodeWin1251 = New-Object System.Windows.Forms.CheckBox
    $script:GUI_CONTROLS.chbEncodeWin1251 = $chbEncodeWin1251
    $chbEncodeWin1251.Name = "chbEncodeWin1251"
    $chbEncodeWin1251.Top = $lblEncodings.Top
    $chbEncodeWin1251.Left = $lblEncodings.Right + $FIELD_MARGIN_RIGHT
    $chbEncodeWin1251.Height = $FIELD_HEIGHT
    $chbEncodeWin1251.Width = 80
    $chbEncodeWin1251.Text = "Win-1251"
    $chbEncodeWin1251.Anchor = "Bottom, Left"
    $gbContentSearchParams.Controls.Add($chbEncodeWin1251)


    $chbEncodeWinUtf8 = New-Object System.Windows.Forms.CheckBox
    $script:GUI_CONTROLS.chbEncodeWinUtf8 = $chbEncodeWinUtf8
    $chbEncodeWinUtf8.Name = "chbEncodeWinUtf8"
    $chbEncodeWinUtf8.Top = $lblEncodings.Top
    $chbEncodeWinUtf8.Left = $chbEncodeWin1251.Right + $FIELD_MARGIN_RIGHT
    $chbEncodeWinUtf8.Height = $FIELD_HEIGHT
    $chbEncodeWinUtf8.Width = 60
    $chbEncodeWinUtf8.Text = "UTF-8"
    $chbEncodeWinUtf8.Anchor = "Bottom, Left"
    $gbContentSearchParams.Controls.Add($chbEncodeWinUtf8)

    $chbEncodeWinUtf16 = New-Object System.Windows.Forms.CheckBox
    $script:GUI_CONTROLS.chbEncodeWinUtf16 = $chbEncodeWinUtf16
    $chbEncodeWinUtf16.Name = "chbEncodeWinUtf16"
    $chbEncodeWinUtf16.Top = $lblEncodings.Top
    $chbEncodeWinUtf16.Left = $chbEncodeWinUtf8.Right + $FIELD_MARGIN_RIGHT
    $chbEncodeWinUtf16.Height = $FIELD_HEIGHT
    $chbEncodeWinUtf16.Width = 70
    $chbEncodeWinUtf16.Text = "UTF-16"
    $chbEncodeWinUtf16.Anchor = "Bottom, Left"
    $gbContentSearchParams.Controls.Add($chbEncodeWinUtf16)

    $chbEncodeWinKoi8 = New-Object System.Windows.Forms.CheckBox
    $script:GUI_CONTROLS.chbEncodeWinKoi8 = $chbEncodeWinKoi8
    $chbEncodeWinKoi8.Name = "chbEncodeWinKoi8"
    $chbEncodeWinKoi8.Top = $lblEncodings.Top
    $chbEncodeWinKoi8.Left = $chbEncodeWinUtf16.Right + $FIELD_MARGIN_RIGHT
    $chbEncodeWinKoi8.Height = $FIELD_HEIGHT
    $chbEncodeWinKoi8.Width = 60
    $chbEncodeWinKoi8.Text = "KOI-8"
    $chbEncodeWinKoi8.Anchor = "Bottom, Left"
    $gbContentSearchParams.Controls.Add($chbEncodeWinKoi8)
    #endregion

    #region Common params group
    $gbCommonParams = New-Object System.Windows.Forms.GroupBox
    $gbCommonParams.Name = "gbCommonParams"
    $gbCommonParams.Text = "Common parameters"
    $gbCommonParams.Top = $gbContentSearchParams.Bottom + $FIELD_MARGIN_BOTTOM
    $gbCommonParams.Left = $FORM_PADDING_LEFT
    $gbCommonParams.Width = $tabInnerWidth
    $gbCommonParams.Height = 70
    $gbCommonParams.Anchor = "Bottom, Left, Right"
    $panel2.Controls.Add($gbCommonParams)
    $groupInnerWidth = $gbCommonParams.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT
    $ttpgbCommonParams = New-Object System.Windows.Forms.ToolTip
    $ttpgbCommonParams.SetToolTip($gbCommonParams, "Applies both to content search and filename search")
    $ttpgbCommonParams.IsBalloon = $true
    #endregion

    #region ---------------- File date start ----------------
    $lbFileDateStart = New-Object System.Windows.Forms.Label
    $lbFileDateStart.Name = "lbFileDateStart"
    $lbFileDateStart.Top = $FORM_PADDING_TOP
    $lbFileDateStart.Text = "File start date:"
    $lbFileDateStart.Left = $FORM_PADDING_LEFT
    $lbFileDateStart.Height = $LABEL_HEIGHT
    $lbFileDateStart.Width = 150
    $lbFileDateStart.AutoEllipsis = $true
    $lbFileDateStart.Anchor = "Bottom, Left"
    $gbCommonParams.Controls.Add($lbFileDateStart)
    $ttpFileDateStart = New-Object System.Windows.Forms.ToolTip
    $ttpFileDateStart.SetToolTip($lbFileDateStart, "Files will be searched from this date and later. If empty, search will be applied to all files")
    $ttpFileDateStart.IsBalloon = $true

    $dpFileDateStart = New-DatePicker
    $script:GUI_CONTROLS.dpFileDateStart = $dpFileDateStart
    $dpFileDateStart.Width = $lbFileDateStart.Width
    $dpFileDateStart.Top = $lbFileDateStart.Bottom
    $dpFileDateStart.Left = $FORM_PADDING_LEFT
    $dpFileDateStart.Anchor = "Bottom, Left"
    $gbCommonParams.Controls.Add($dpFileDateStart)
    #end region

    #region ---------------- File date end ----------------
    $lbFileDateEnd = New-Object System.Windows.Forms.Label
    $lbFileDateEnd.Name = "lbFileDateEnd"
    $lbFileDateEnd.Top = $FORM_PADDING_TOP
    $lbFileDateEnd.Text = "File end date:"
    $lbFileDateEnd.Left = $lbFileDateStart.Right + $FIELD_MARGIN_RIGHT * 3
    $lbFileDateEnd.Height = $LABEL_HEIGHT
    $lbFileDateEnd.Width = 150
    $lbFileDateEnd.AutoEllipsis = $true
    $lbFileDateEnd.Anchor = "Bottom, Left"
    $gbCommonParams.Controls.Add($lbFileDateEnd)
    $ttpFileDateEnd = New-Object System.Windows.Forms.ToolTip
    $ttpFileDateEnd.SetToolTip($lbFileDateEnd, "Files will be searched to this date and earlier. If empty, search will be applied to all files")
    $ttpFileDateEnd.IsBalloon = $true

    $dpFileDateEnd = New-DatePicker
    $script:GUI_CONTROLS.dpFileDateEnd = $dpFileDateEnd
    $dpFileDateEnd.Width = 150
    $dpFileDateEnd.Top = $lbFileDateEnd.Bottom
    $dpFileDateEnd.Left = $lbFileDateEnd.Left
    $dpFileDateEnd.Anchor = "Bottom, Left"
    $gbCommonParams.Controls.Add($dpFileDateEnd)
    #end region

    #region ---------- Saved file checkbox --------------------------------
    $chbAutoSaveResults = New-Object System.Windows.Forms.CheckBox
    $script:GUI_CONTROLS.chbAutoSaveResults = $chbAutoSaveResults
    $chbAutoSaveResults.Name = "chbAutoSaveResults"
    $chbAutoSaveResults.Top = $gbCommonParams.Bottom + $FIELD_MARGIN_BOTTOM
    $chbAutoSaveResults.Left = $FORM_PADDING_LEFT
    $chbAutoSaveResults.Height = $FIELD_HEIGHT
    $chbAutoSaveResults.Width = 115
    $chbAutoSaveResults.Text = "Auto-save results"
    $chbAutoSaveResults.Checked = $false
    $chbAutoSaveResults.Anchor = "Bottom, Left"
    $panel2.Controls.Add($chbAutoSaveResults)
    #$chbAutoSaveResults.BackColor = [System.Drawing.Color]::Red
    $chbAutoSaveResults.Add_CheckedChanged({
            param($s, $e)
   
            $parent = $s.Parent
            $txtAutoSaveResults = $parent.Controls["txtAutoSaveResults"]
            $btnAutoSaveResults = $parent.Controls["btnAutoSaveResults"]

            $txtAutoSaveResults.Visible = $s.Checked
            $btnAutoSaveResults.Visible = $s.Checked
        })


    $txtAutoSaveResults = New-Object System.Windows.Forms.TextBox
    $script:GUI_CONTROLS.txtAutoSaveResults = $txtAutoSaveResults
    $txtAutoSaveResults.Name = "txtAutoSaveResults"
    $txtAutoSaveResults.Top = $chbAutoSaveResults.Top
    $txtAutoSaveResults.Left = $chbAutoSaveResults.Right + $FIELD_MARGIN_RIGHT
    $txtAutoSaveResults.Height = $FIELD_HEIGHT
    $txtAutoSaveResults.Width = 195
    $txtAutoSaveResults.Visible = $false
    $txtAutoSaveResults.Anchor = "Bottom, Left"
    $panel2.Controls.Add($txtAutoSaveResults)

    $btnAutoSaveResults = New-Object System.Windows.Forms.Button
    $btnAutoSaveResults.Name = "btnAutoSaveResults"
    $btnAutoSaveResults.Text = "..."
    $btnAutoSaveResults.Top = $txtAutoSaveResults.Top - 1
    $btnAutoSaveResults.Left = $txtAutoSaveResults.Right - 2
    $btnAutoSaveResults.Height = $txtAutoSaveResults.Height
    $btnAutoSaveResults.Width = 23
    $btnAutoSaveResults.Visible = $false
    $btnAutoSaveResults.Anchor = "Bottom, Left"
    $panel2.Controls.Add($btnAutoSaveResults)
    $btnAutoSaveResults.Add_Click({
            param($s, $e)
            $fileDialog = New-Object System.Windows.Forms.SaveFileDialog
            $fileDialog.Filter = "CSV files (*.csv)|*.csv|Text files (*.txt)|*.txt|All files (*.*)|*.*"
            if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $parent = $s.Parent
                $txtAutoSaveResults = $parent.Controls["txtAutoSaveResults"]
                $txtAutoSaveResults.Text = $fileDialog.FileName
            }
        })
    #endregion
}

function Get-EncodingDefaultValues {
    param (
        [string]$encoding
    )

    $result = @{
        "windows-1251" = $true
        "utf-8"        = $false
        "utf-16"       = $false
        "koi8-r"       = $false
    }

    $encoding = $encoding.Trim().ToLower()

    if ([string]::IsNullOrEmpty($encoding)) { return $result }

    $codes = Split-StringToArray -str $encoding
    
    foreach ($code in $codes) {
        $codeName = Get-CanonicalEncodingName -name $code
        if ($codeName.Length -ne 0) { $result[$codeName] = $true }
    }

    return $result
}

function Set-TabConfigEncodings {
    param (
        [string]$encodings
    )

    if (-not $encodings) { 
        $script:GUI_CONTROLS.chbEncodeWin1251.Checked = $false
        $script:GUI_CONTROLS.chbEncodeWinUtf8.Checked = $false
        $script:GUI_CONTROLS.chbEncodeWinUtf16.Checked = $false
        $script:GUI_CONTROLS.chbEncodeWinKoi8.Checked = $false
        return 
    }
    
    $encList = Get-EncodingDefaultValues -encoding $encodings
    $script:GUI_CONTROLS.chbEncodeWin1251.Checked = $encList["windows-1251"]
    $script:GUI_CONTROLS.chbEncodeWinUtf8.Checked = $encList["utf-8"]
    $script:GUI_CONTROLS.chbEncodeWinUtf16.Checked = $encList["utf-16"]
    $script:GUI_CONTROLS.chbEncodeWinKoi8.Checked = $encList["koi8-r"]
}

function Get-TabConfigEncodings {
    $result = @()

    if ($script:GUI_CONTROLS.chbEncodeWin1251.Checked) { $result += "windows-1251" }
    if ($script:GUI_CONTROLS.chbEncodeWinUtf8.Checked) { $result += "utf-8" }
    if ($script:GUI_CONTROLS.chbEncodeWinUtf16.Checked) { $result += "utf-16" }
    if ($script:GUI_CONTROLS.chbEncodeWinKoi8.Checked) { $result += "koi8-r" }

    if ($result.Length -eq 0) { return "" }
    return $result -join ", "
}

function Set-TabConfigParams {
    param (
        [hashtable]$params,
        [boolean]$clear = $false
    )
    
    if ($params.ContainsKey('locations')) {
        Clear-LocationsGrid
        Set-LocationsToGrid -locations $params.locations | Out-Null
    }
    elseif ($clear) { Clear-LocationsGrid | Out-Null }
    

    if ($params.ContainsKey('searchPatterns')) {
        Clear-SearchPatternsGrid
        Set-SearchPatternsToGrid -searchPatterns $params.searchPatterns | Out-Null
    }
    elseif ($clear) { Clear-LocationsGrid | Out-Null }
    

    if ($params.ContainsKey('allowedMasks')) { $script:GUI_CONTROLS.txtAllowedMasks.Text = $params.allowedMasks }
    elseif ($clear) { $script:GUI_CONTROLS.txtAllowedMasks.Text = "" }
    
    
    if ($params.ContainsKey('excludedMasks')) { $script:GUI_CONTROLS.txtExcludedMasks.Text = $params.excludedMasks }
    elseif ($clear) { $script:GUI_CONTROLS.txtExcludedMasks.Text = "" }
    

    if ($params.ContainsKey('maxFileSize')) { $script:GUI_CONTROLS.cbMaxFileSize.Text = $params.maxFileSize }
    elseif ($clear) { $script:GUI_CONTROLS.cbMaxFileSize.Text = "" }

    if ($params.ContainsKey('encodings')) { Set-TabConfigEncodings -encodings $params.encodings }
    elseif ($clear) { Set-TabConfigEncodings -encodings $null }
    
    if ($params.ContainsKey('resultFilePath')) {
        $script:GUI_CONTROLS.chbAutoSaveResults.Checked = $params.ResultFilePath.Length -gt 0
        $script:GUI_CONTROLS.txtAutoSaveResults.Text = $params.resultFilePath
    }
    elseif ($clear) {
        $script:GUI_CONTROLS.chbAutoSaveResults.Checked = $false 
        $script:GUI_CONTROLS.txtAutoSaveResults.Text = ""
    }

    if ($params.ContainsKey('fileDateStart')) { $script:GUI_CONTROLS.dpFileDateStart.Text = $params.fileDateStart }
    elseif ($clear) { $script:GUI_CONTROLS.dpFileDateStart.Text = "" }

    if ($params.ContainsKey('fileDateEnd')) { $script:GUI_CONTROLS.dpFileDateEnd.Text = $params.fileDateEnd }
    elseif ($clear) { $script:GUI_CONTROLS.dpFileDateEnd.Text = "" }
}