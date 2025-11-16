. "$PSScriptRoot/ui/alerts/alerts.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/ui/advancedGrid/advancedGrid.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"
. "$PSScriptRoot/../helpers/forms.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/formConstants.ps1"

function Initialize-GridLocations {
    param (
        [System.Windows.Forms.Form]$form,
        [System.Windows.Forms.Control]$container
    )

    $columns = Get-GridLocationsColumns

    $onCellDoubleClick = { 
        Initialize-LocationModalForm -form $form -mode "edit" | Out-Null 
    }

    $onKeyDown = {
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Insert) { Initialize-LocationModalForm -form $form -mode "add" | Out-Null }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { 
            Initialize-LocationModalForm -form $form -mode "edit" | Out-Null 
            $_.SuppressKeyPress = $true
        }
    }

    $buttons = @(
        @{ 
            "type"    = "button"
            "name"    = "Add"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { Initialize-LocationModalForm -form $form -mode "add" | Out-Null }
        },

        @{ 
            "type"    = "button"
            "name"    = "Edit"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { Initialize-LocationModalForm -form $form -mode "edit" | Out-Null }
        },

        @{ 
            "type"    = "button"
            "name"    = "Remove"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { 
                Remove-LocationsFromGrid | Out-Null 
                $script:APP_CONTEXT.session.unsaved = $true
            }
        }
    )

    $grid = Initialize-AdvancedGrid `
        -Container $container `
        -Columns $columns `
        -Buttons $buttons `
        -HeaderLabelHeight $LABEL_HEIGHT `
        -HeaderLabelWidth 100 `
        -PaddingTop $FORM_PADDING_TOP `
        -PaddingBottom $FORM_PADDING_BOTTOM `
        -PaddingLeft $FORM_PADDING_LEFT `
        -PaddingRight $FORM_PADDING_RIGHT `
        -HeaderLabelText "Search Locations:" `
        -HeaderLabelTooltip "Locations to search. If specified host only, will try to resolve all shared folders" `
        -ReadOnly $true `
        -MultiSelect $true `
        -CheckboxColumn "Selected" `
        -DefaulExportFileName "locations.csv" `
        -OnKeyDown $onKeyDown `
        -OnCellDoubleClick $onCellDoubleClick

    $script:GUI_CONTROLS.gridLocations = $grid
}

function Get-GridLocationsColumns {

    $colType = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colType.Name = "Type"
    $colType.HeaderText = "Type"
    $colType.FillWeight = 20
    $colType.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colValue = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colValue.Name = "Value"
    $colValue.HeaderText = "Value"
    $colValue.FillWeight = 140
    $colValue.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDesc.Name = "Desc"
    $colDesc.HeaderText = "Desc"
    $colDesc.FillWeight = 40
    $colDesc.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    return $($colType, $colValue, $colDesc)
}

function Initialize-LocationModalForm {
    param (
        [System.Windows.Forms.Form]$form,   
        [string]$mode)

    $grid = $script:GUI_CONTROLS.gridLocations
    $currentRow = $grid.CurrentRow

    $formChild = New-Object System.Windows.Forms.Form

    $formChild.Tag = @{
        mode       = $mode
        currentRow = $currentRow
    }
    
    $formChild.Text = if ($mode -eq "add") { "Add Location" } else { "Edit Location" }
    $formChild.StartPosition = "CenterParent"
    $formChild.Width = 400
    $formChild.Height = 250
    $formChild.MinimumSize = "250,250"
    $formChild.KeyPreview = $true
    $formChild.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $this.Close() } })
    
    $innerWidth = $formChild.ClientSize.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT

    #region ---------- Location Type ----------------------------------
    $lbLocationType = New-Object System.Windows.Forms.Label
    $lbLocationType.Name = "lbLocationType"
    $lbLocationType.Text = "Location Type*:"
    $lbLocationType.Top = $FORM_PADDING_TOP
    $lbLocationType.Left = $FORM_PADDING_LEFT
    $lbLocationType.Height = $LABEL_HEIGHT
    $lbLocationType.Width = $innerWidth
    $lbLocationType.AutoEllipsis = $true
    $lbLocationType.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($lbLocationType)

    $cmbLocationType = New-Object System.Windows.Forms.ComboBox
    $cmbLocationType.Name = "cmbLocationType"
    $cmbLocationType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbLocationType.Top = $lbLocationType.Bottom
    $cmbLocationType.Left = $FORM_PADDING_LEFT
    $cmbLocationType.Height = $FIELD_HEIGHT
    $cmbLocationType.Width = $innerWidth
    $cmbLocationType.Items.Add("Folder")
    $cmbLocationType.Items.Add("IP range")
    $cmbLocationType.Items.Add("Host")
    $cmbLocationType.Text = "Folder"
    $cmbLocationType.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($cmbLocationType)
    
    $cmbLocationType.Add_SelectedIndexChanged({
            param($s, $e)
            $selected = $s.SelectedItem
            Set-LocationType -modalForm $formChild -type $selected
        })
    #endregion

    #region ---------- Folder Label & Textbox ----------------------------
    $lbFolderPath = New-Object System.Windows.Forms.Label
    $lbFolderPath.Name = "lbFolderPath"
    $lbFolderPath.Text = "Folder Path*:"
    $lbFolderPath.Top = $cmbLocationType.Bottom + $FIELD_MARGIN_BOTTOM
    $lbFolderPath.Left = $FORM_PADDING_LEFT
    $lbFolderPath.Height = $LABEL_HEIGHT
    $lbFolderPath.Width = $innerWidth
    $lbFolderPath.Anchor = "Top, Left, Right"
    $lbFolderPath.AutoEllipsis = $true
    $formChild.Controls.Add($lbFolderPath)
    $ttpFolderPath = New-Object System.Windows.Forms.ToolTip
    $ttpFolderPath.SetToolTip($lbFolderPath, "Folder Path. Must be a valid local or UNC path (like \\server\share). Not just a host name")
    $ttpFolderPath.IsBalloon = $true
    
    $txtFolderPath = New-Object System.Windows.Forms.TextBox
    $txtFolderPath.Name = "txtFolderPath"
    $txtFolderPath.Top = $lbFolderPath.Bottom
    $txtFolderPath.Left = $FORM_PADDING_LEFT
    $txtFolderPath.Height = $FIELD_HEIGHT
    $txtFolderPath.Width = $innerWidth - 80
    $txtFolderPath.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($txtFolderPath)

    $btnFolderBrowse = New-Object System.Windows.Forms.Button
    $btnFolderBrowse.Name = "btnFolderBrowse"
    $btnFolderBrowse.Text = "Browse..."
    $btnFolderBrowse.Top = $txtFolderPath.Top - 1
    $btnFolderBrowse.Left = $txtFolderPath.Right - 2
    $btnFolderBrowse.Width = 80
    $btnFolderBrowse.Height = $txtFolderPath.Height + 2 #borders is 2�1 px
    $btnFolderBrowse.Anchor = "Top, Right"
    $formChild.Controls.Add($btnFolderBrowse)

    $btnFolderBrowse.Add_Click({
            param($s, $e)

            $txtFolderPath = $s.Parent.Controls["txtFolderPath"]
            $folderDlg = New-Object System.Windows.Forms.FolderBrowserDialog

            if ([System.IO.Directory]::Exists($txtFolderPath.Text)) { $folderDlg.SelectedPath = $txtFolderPath.Text }

            if ($folderDlg.ShowDialog() -eq "OK") {
                $txtFolderPath.Text = $folderDlg.SelectedPath
            }
        }) 

    #endregion

    #region ---------- IP Range ------------------------------------------
    $lbStartIp = New-Object System.Windows.Forms.Label
    $lbStartIp.Name = "lbStartIp"
    $lbStartIp.Text = "Start IP*:"
    $lbStartIp.Top = $cmbLocationType.Bottom + $FIELD_MARGIN_BOTTOM
    $lbStartIp.Left = $FORM_PADDING_LEFT
    $lbStartIp.Height = $LABEL_HEIGHT
    $lbStartIp.Width = 100
    $lbStartIp.AutoEllipsis = $true
    $formChild.Controls.Add($lbStartIp)
    
    $txtStartIp = New-Object System.Windows.Forms.TextBox
    $txtStartIp.Name = "txtStartIp"
    $txtStartIp.Top = $lbStartIp.Bottom
    $txtStartIp.Left = $FORM_PADDING_LEFT
    $txtStartIp.Height = $FIELD_HEIGHT
    $txtStartIp.Width = 100
    $formChild.Controls.Add($txtStartIp)


    $lbEndIp = New-Object System.Windows.Forms.Label
    $lbEndIp.Name = "lbEndIp"
    $lbEndIp.Text = "End IP*:"
    $lbEndIp.Top = $cmbLocationType.Bottom + $FIELD_MARGIN_BOTTOM
    $lbEndIp.Left = $lbStartIp.Right + $FIELD_MARGIN_RIGHT
    $lbEndIp.Height = $LABEL_HEIGHT
    $lbEndIp.Width = 100
    $lbEndIp.AutoEllipsis = $true
    $formChild.Controls.Add($lbEndIp)

    $txtEndIp = New-Object System.Windows.Forms.TextBox
    $txtEndIp.Name = "txtEndIp"
    $txtEndIp.Top = $lbEndIp.Bottom
    $txtEndIp.Left = $lbStartIp.Right + $FIELD_MARGIN_RIGHT
    $txtEndIp.Height = $FIELD_HEIGHT
    $txtEndIp.Width = 100
    $formChild.Controls.Add($txtEndIp)

    $lbExtraFolder = New-Object System.Windows.Forms.Label
    $lbExtraFolder.Name = "lbExtraFolder"
    $lbExtraFolder.Text = "Folder:"
    $lbExtraFolder.Top = $cmbLocationType.Bottom + $FIELD_MARGIN_BOTTOM
    $lbExtraFolder.Left = $lbEndIp.Right + $FIELD_MARGIN_RIGHT
    $lbExtraFolder.Height = $LABEL_HEIGHT
    $lbExtraFolder.Width = $innerWidth - $lbStartIp.Width - $lbEndIp.Width - $FIELD_MARGIN_RIGHT - $FIELD_MARGIN_RIGHT
    $lbExtraFolder.Anchor = "Top, Left, Right"
    $lbExtraFolder.AutoEllipsis = $true
    $formChild.Controls.Add($lbExtraFolder)
    $ttpExtraFolder = New-Object System.Windows.Forms.ToolTip
    $ttpExtraFolder.SetToolTip($lbExtraFolder, "If specified, will search in this folder for each IP in range. Otherwise, will try to discover all shared folders for each IP")
    $ttpExtraFolder.IsBalloon = $true

    $txtExtraFolder = New-Object System.Windows.Forms.TextBox
    $txtExtraFolder.Name = "txtExtraFolder"
    $txtExtraFolder.Top = $lbExtraFolder.Bottom
    $txtExtraFolder.Left = $lbEndIp.Right + $FIELD_MARGIN_RIGHT
    $txtExtraFolder.Height = $FIELD_HEIGHT
    $txtExtraFolder.Width = $innerWidth - $lbStartIp.Width - $lbEndIp.Width - $FIELD_MARGIN_RIGHT - $FIELD_MARGIN_RIGHT
    $txtExtraFolder.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($txtExtraFolder)
    #endregion

    #region ---------- Hostname ------------------------------------------
    $lbHostname = New-Object System.Windows.Forms.Label
    $lbHostname.Name = "lbHostname"
    $lbHostname.Text = "Hostname*:"
    $lbHostname.Top = $cmbLocationType.Bottom + $FIELD_MARGIN_BOTTOM
    $lbHostname.Left = $FORM_PADDING_LEFT
    $lbHostname.Height = $LABEL_HEIGHT
    $lbHostname.Width = $innerWidth
    $lbHostname.Anchor = "Top, Left, Right"
    $lbHostname.AutoEllipsis = $true
    $formChild.Controls.Add($lbHostname)
    $ttpHostname = New-Object System.Windows.Forms.ToolTip
    $ttpHostname.SetToolTip($lbHostname, "Hostname or IP address without path. Will try to discover all shared folders for this host")
    $ttpHostname.IsBalloon = $true

    $txtHostname = New-Object System.Windows.Forms.TextBox
    $txtHostname.Name = "txtHostname"
    $txtHostname.Top = $lbHostname.Bottom
    $txtHostname.Left = $FORM_PADDING_LEFT
    $txtHostname.Height = $FIELD_HEIGHT
    $txtHostname.Width = $innerWidth
    $txtHostname.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($txtHostname)
    #endregion

    #region ---------- Location description -------------------------------
    $lbLocationDesc = New-Object System.Windows.Forms.Label
    $lbLocationDesc.Name = "lbLocationDesc"
    $lbLocationDesc.Text = "Location description:"
    $lbLocationDesc.Top = $txtHostname.Bottom + $FIELD_MARGIN_BOTTOM
    $lbLocationDesc.Left = $FORM_PADDING_LEFT
    $lbLocationDesc.Height = $LABEL_HEIGHT
    $lbLocationDesc.Width = $innerWidth
    $lbLocationDesc.Anchor = "Top, Left, Right"
    $lbLocationDesc.AutoEllipsis = $true
    $formChild.Controls.Add($lbLocationDesc)
    
    $txtLocationDesc = New-Object System.Windows.Forms.TextBox
    $txtLocationDesc.Name = "txtLocationDesc"
    $txtLocationDesc.Top = $lbLocationDesc.Bottom
    $txtLocationDesc.Left = $FORM_PADDING_LEFT
    $txtLocationDesc.Height = $FIELD_HEIGHT * 4
    $txtLocationDesc.Width = $innerWidth
    $txtLocationDesc.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($txtLocationDesc)
    #endregion

    #region ---------- OK Button --------------------------------------

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Name = "btnOK"
    $btnOK.Text = "OK"
    $btnOK.Top = $formChild.ClientSize.Height - 30 - $FORM_PADDING_BOTTOM
    $btnOK.Left = $innerWidth - 80 - 80 - 10
    $btnOK.Size = '80,30'
    $btnOK.Anchor = "Right, Bottom"
    $btnOK.Add_Click({ 
            param( $s, $e)
            
            $modalForm = $s.FindForm()

            $mode = $modalForm.Tag.mode
            $currentRow = $modalForm.Tag.currentRow

            $validationResult = Test-ValidateLocationForm -modalForm $modalForm
            if (-not $validationResult) { return }

            $data = Get-LocationFormData -modalForm $modalForm
            if ($null -eq $data) { return }
            if ($mode -eq "add") { $currentRow = $null }

            Add-LocationValueToGrid -currentRow $currentRow -data $data | Out-Null
            $script:APP_CONTEXT.session.unsaved = $true

            $formChild.Close()
        })
    $formChild.Controls.Add($btnOK)
    #endregion

    #region ---------- Cancel Button --------------------------------------
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Name = "btnCancel"
    $btnCancel.Text = "Cancel"
    $btnCancel.Top = $formChild.ClientSize.Height - 30 - $FORM_PADDING_BOTTOM
    $btnCancel.Left = $btnOK.Right + 20
    $btnCancel.Size = '80,30'
    $btnCancel.Anchor = "Right, Bottom"
    $btnCancel.Add_Click({ $formChild.Close() })
    $formChild.Controls.Add($btnCancel)
    #endregion

    if ($mode -eq "add") {
        Set-LocationType -modalForm $formChild -type "Folder" | Out-Null
    }
    else {
        if (-not $currentRow) { return }
        Set-LocationCurrentRowValue -row $currentRow -modalForm $formChild | Out-Null
    }

    $formChild.ShowDialog($form) 
}

function Set-LocationType {
    param (
        [System.Windows.Forms.Form]$modalForm,
        [string]$type
    )

    if ($type -eq "Folder" -or $type -eq "IP Range" -or $type -eq "Host") { $modalForm.Controls["cmbLocationType"].Text = $type }

    $modalForm.Controls["lbFolderPath"].Visible = $type -eq "Folder"
    $modalForm.Controls["txtFolderPath"].Visible = $type -eq "Folder"
    $modalForm.Controls["btnFolderBrowse"].Visible = $type -eq "Folder"
    $modalForm.Controls["lbStartIp"].Visible = $type -eq "IP Range"
    $modalForm.Controls["txtStartIp"].Visible = $type -eq "IP Range"
    $modalForm.Controls["lbEndIp"].Visible = $type -eq "IP Range"
    $modalForm.Controls["txtEndIp"].Visible = $type -eq "IP Range"
    $modalForm.Controls["lbExtraFolder"].Visible = $type -eq "IP Range"
    $modalForm.Controls["txtExtraFolder"].Visible = $type -eq "IP Range"
    $modalForm.Controls["lbHostname"].Visible = $type -eq "Host"
    $modalForm.Controls["txtHostname"].Visible = $type -eq "Host"
}

function Test-ValidateLocationForm {
    param (
        [System.Windows.Forms.Form]$modalForm
    )

    $type = $modalForm.Controls["cmbLocationType"].SelectedItem

    if ($type -eq "Folder") {
        $folderPath = $modalForm.Controls["txtFolderPath"].Text.Trim() 
        if ([string]::IsNullOrEmpty($folderPath) -or -not (Test-Path -LiteralPath $folderPath)) {
            Show-Error "Folder not found: $folderPath"
            return $false
        }

        return $true

    }
    
    if ($type -eq "IP Range") {
        $startIp = $modalForm.Controls["txtStartIp"].Text.Trim()
        $endIp = $modalForm.Controls["txtEndIp"].Text.Trim()

        if ($startIp -eq "" -or $endIp -eq "") {
            Show-Error "Start and End IP cannot be empty" 
            return $false 
        }

        $err = Test-IsValidIpRange -startIp $startIp -endIp $endIp
        if ($null -ne $err) {
            Show-Error $err
            return $false
        }

        return $true
    }

    if ($type -eq "Host") {
        $hostName = $modalForm.Controls["txtHostname"].Text.Trim()

        $err = Test-IsValidHostName -hostName $hostName
        if ($null -ne $err) {
            Show-Error $err
            return $false
        }

        return $true
    }

    Show-Error "Invalid location type: $type"

    return $false
}

function Get-LocationFormData {
    param(
        [System.Windows.Forms.Form]$modalForm
    )

    $type = $modalForm.Controls["cmbLocationType"].SelectedItem

    $data = @{
        Type = $type
        Desc = $modalForm.Controls["txtLocationDesc"].Text.Trim()
    }

    $mode = $modalForm.Tag.mode
    $currentRow = $modalForm.Tag.currentRow
    
    if ($mode -eq "add") { $data.Selected = $true }
    else { $data.Selected = [bool]$currentRow.DataBoundItem["Selected"] }


    if ($type -eq "Folder") {
        $data.Value = $modalForm.Controls["txtFolderPath"].Text.Trim()
    }
    elseif ($type -eq "IP Range") {
        $start = $modalForm.Controls["txtStartIp"].Text.Trim()
        $end = $modalForm.Controls["txtEndIp"].Text.Trim()
        
        $val = "$(Get-NormalizedIp $start) - $(Get-NormalizedIp $end)"

        $extraFolder = $modalForm.Controls["txtExtraFolder"].Text.Trim()
        if (-not [string]::IsNullOrEmpty($extraFolder)) {
            $val = $val + (Join-Path " " $extraFolder)
        }

        $data.Value = $val
    }
    elseif ($type -eq "Host") {
        $data.Value = $modalForm.Controls["txtHostname"].Text.Trim()
    }
    else {
        return $null
    }

    return $data
}

function Add-LocationValueToGrid {
    param (
        [System.Windows.Forms.DataGridViewRow]$currentRow,
        [hashtable]$data
    )

    $grid = $script:GUI_CONTROLS.gridLocations

    if (-not $data.ContainsKey("Type") -or -not $data.ContainsKey("Value")) { return }

    if (-not $currentRow) { Add-GridRow -grid $grid -values $data -selectAddedRow $true }
    else { Update-GridRow -grid $grid -row $currentRow -values $data }
}

function Set-LocationCurrentRowValue {
    param (
        [System.Windows.Forms.DataGridViewRow]$row,
        [System.Windows.Forms.Form]$modalForm
    )

    if ($null -eq $row) { return $null }

    $type = $row.Cells["Type"].Value
    $value = $row.Cells["Value"].Value
    $desc = $row.Cells["Desc"].Value

    Set-LocationType -modalForm $modalForm -type $type

    $modalForm.Controls["txtLocationDesc"].Text = $desc

    if ($type -eq "Folder") {
        $modalForm.Controls["txtFolderPath"].Text = $value
    }
    elseif ($type -eq "IP Range") {
        $parts = Split-IpRangeToParts $value
        if ($null -eq $parts) { return $false }

        $modalForm.Controls["txtStartIp"].Text = $parts.startIp
        $modalForm.Controls["txtEndIp"].Text = $parts.endIp
        $modalForm.Controls["txtExtraFolder"].Text = $parts.folder
    }
    elseif ($type -eq "Host") {
        $modalForm.Controls["txtHostname"].Text = $value
    }

    return $true
}

function Remove-LocationsFromGrid {
    $grid = $script:GUI_CONTROLS.gridLocations
    Remove-SelectedGridRows -grid $grid
}

function Clear-LocationsGrid {
    $grid = $script:GUI_CONTROLS.gridLocations
    Clear-GridRows -Grid $grid 
}

function Set-LocationsToGrid {
    param (
        [hashtable[]]$locations
    )

    if (-not $locations) { 
        Clear-LocationsGrid
        return 
    }

    foreach ($loc in $locations) {
        Add-LocationValueToGrid -currentRow $null -data $loc
    }

    Set-GridCursorPosition -grid $script:GUI_CONTROLS.gridLocations -rowIndex 0
}