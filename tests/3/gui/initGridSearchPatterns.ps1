. "$PSScriptRoot/ui/alerts/alerts.ps1"
. "$PSScriptRoot/ui/advancedGrid/advancedGrid.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/../helpers/forms.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/formConstants.ps1"

$script:headerChecked = $false
function Initialize-GridSearchPatterns {
    param (
        [System.Windows.Forms.Form]$form,
        [System.Windows.Forms.Control]$container
    )

    $columns = Get-GridSearchPatternsColumns

    $onCellDoubleClick = { 
        Initialize-SearchPatternModalForm -form $form -mode "edit" | Out-Null 
    }

    $onKeyDown = {
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Insert) { Initialize-SearchPatternModalForm -form $form -mode "add" | Out-Null }
        elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { 
            Initialize-SearchPatternModalForm -form $form -mode "edit" | Out-Null 
            $_.SuppressKeyPress = $true
        }
    }


    $buttons = @(
        @{ 
            "type"    = "button"
            "name"    = "Add"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { Initialize-SearchPatternModalForm -form $form -mode "add" | Out-Null }
        },

        @{ 
            "type"    = "button"
            "name"    = "Edit"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { Initialize-SearchPatternModalForm -form $form -mode "edit" | Out-Null }
        },

        @{ 
            "type"    = "button"
            "name"    = "Remove"
            "width"   = 60
            "height"  = $LABEL_HEIGHT + 2 #borders is 2 px
            "onClick" = { 
                Remove-SearchPatternFromGrid | Out-Null 
                $script:APP_CONTEXT.session.unsaved = $true
            }
        }
    )

    $grid = Initialize-AdvancedGrid `
        -Container $container `
        -Columns $columns `
        -Buttons $buttons `
        -Height ($container.ClientSize.Height - 320) `
        -HeaderLabelHeight $LABEL_HEIGHT `
        -HeaderLabelWidth 100 `
        -PaddingTop $FORM_PADDING_TOP `
        -PaddingBottom $FORM_PADDING_BOTTOM `
        -PaddingLeft $FORM_PADDING_LEFT `
        -PaddingRight $FORM_PADDING_RIGHT `
        -HeaderLabelText "Search Patterns:" `
        -HeaderLabelTooltip "Regex patterns to search. Can be for file names or for content search" `
        -ReadOnly $true `
        -MultiSelect $true `
        -CheckboxColumn "Selected" `
        -DefaulExportFileName "patterns.csv" `
        -OnKeyDown $onKeyDown `
        -OnCellDoubleClick $onCellDoubleClick

    $script:GUI_CONTROLS.gridSearchPatterns = $grid


    return $grid
}

function Get-GridSearchPatternsColumns {
    $colType = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colType.Name = "Type"
    $colType.HeaderText = "Type"
    $colType.FillWeight = 20
    $colType.ReadOnly = $true
    $colType.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True
    
    $colPattern = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPattern.Name = "Pattern"
    $colPattern.HeaderText = "Pattern"
    $colPattern.FillWeight = 140
    $colPattern.ReadOnly = $true
    $colPattern.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True
    $colPattern.DefaultCellStyle.Font = New-Object System.Drawing.Font("Courier New", 9)

    $colDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDesc.Name = "Desc"
    $colDesc.HeaderText = "Desc"
    $colDesc.FillWeight = 40
    $colDesc.ReadOnly = $true
    $colDesc.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colIncludedMasks = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colIncludedMasks.Name = "IncludedMasks"
    $colIncludedMasks.HeaderText = "Included masks"
    $colIncludedMasks.FillWeight = 40
    $colIncludedMasks.Visible = $false
    $colIncludedMasks.ReadOnly = $true
    $colIncludedMasks.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colExcludedMasks = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colExcludedMasks.Name = "ExcludedMasks"
    $colExcludedMasks.HeaderText = "Excluded masks"
    $colExcludedMasks.FillWeight = 40
    $colExcludedMasks.Visible = $false
    $colExcludedMasks.ReadOnly = $true
    $colExcludedMasks.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colMaxContentLength = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMaxContentLength.Name = "MaxContentLength"
    $colMaxContentLength.HeaderText = "Max content Length"
    $colMaxContentLength.FillWeight = 20
    $colMaxContentLength.Visible = $false
    $colMaxContentLength.ReadOnly = $true
    $colMaxContentLength.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colMinFileSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMinFileSize.Name = "MinFileSize"
    $colMinFileSize.HeaderText = "Min file size"
    $colMinFileSize.FillWeight = 20
    $colMinFileSize.Visible = $false
    $colMinFileSize.ReadOnly = $true
    $colMinFileSize.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True
    
    $colMaxFileSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMaxFileSize.Name = "MaxFileSize"
    $colMaxFileSize.HeaderText = "Max file size"
    $colMaxFileSize.FillWeight = 20
    $colMaxFileSize.Visible = $false
    $colMaxFileSize.ReadOnly = $true
    $colMaxFileSize.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    return $($colType, $colPattern, $colDesc, $colIncludedMasks, $colExcludedMasks, $colMaxContentLength, $colMinFileSize, $colMaxFileSize)
}

function Initialize-SearchPatternModalForm {
    param (
        [System.Windows.Forms.Form]$form,   
        [string]$mode)

    $grid = $script:GUI_CONTROLS.gridSearchPatterns

    $currentRow = $grid.CurrentRow

    $formChild = New-Object System.Windows.Forms.Form
    $formChild.Tag = @{
        mode       = $mode
        currentRow = $currentRow
    }
    $formChild.Text = if ($mode -eq "add") { "Add Pattern" } else { "Edit Pattern" }
    $formChild.StartPosition = "CenterParent"
    $formChild.Width = 550
    $formChild.Height = 610
    $formChild.MinimumSize = "250,420"
    $formChild.KeyPreview = $true
    $formChild.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $this.Close() } })

    $innerWidth = $formChild.ClientSize.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT

    #region ---------- Pattern Type ----------------------------------
    $lbSearchPatternType = New-Object System.Windows.Forms.Label
    $lbSearchPatternType.Name = "lbSearchPatternType"
    $lbSearchPatternType.Text = "Pattern Type*:"
    $lbSearchPatternType.Top = $FORM_PADDING_TOP
    $lbSearchPatternType.Left = $FORM_PADDING_LEFT
    $lbSearchPatternType.Height = $LABEL_HEIGHT
    $lbSearchPatternType.Width = $innerWidth
    $lbSearchPatternType.AutoEllipsis = $true
    $lbSearchPatternType.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($lbSearchPatternType)

    $cmbSearchPatternType = New-Object System.Windows.Forms.ComboBox
    $cmbSearchPatternType.Name = "cmbSearchPatternType"
    $cmbSearchPatternType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbSearchPatternType.Top = $lbSearchPatternType.Bottom
    $cmbSearchPatternType.Left = $FORM_PADDING_LEFT
    $cmbSearchPatternType.Height = $FIELD_HEIGHT
    $cmbSearchPatternType.Width = $innerWidth
    $cmbSearchPatternType.Items.Add("Content")
    $cmbSearchPatternType.Items.Add("Filename")
    $cmbSearchPatternType.Text = "Content"
    $cmbSearchPatternType.Anchor = "Top, Left, Right"
    $formChild.Controls.Add($cmbSearchPatternType)
    
    $cmbSearchPatternType.Add_SelectedIndexChanged({
            param($s, $e)
            $selected = $s.SelectedItem
            Set-SearchPatternType -modalForm $formChild -type $selected
        })
    #endregion

    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Name = "patternsSplitContainer"
    $splitContainer.Dock = [System.Windows.Forms.DockStyle]::None
    $splitContainer.Orientation = 'Horizontal'
    $splitContainer.Top = $cmbSearchPatternType.Bottom + $FIELD_MARGIN_BOTTOM
    $splitContainer.Height = 260
    $splitContainer.Width = $formChild.ClientSize.Width
    $splitContainer.Anchor = "Top, Bottom, Left, Right"
    $splitContainer.SplitterDistance = 150
    $formChild.Controls.Add($splitContainer)
    
    $panel1 = New-Object System.Windows.Forms.Panel
    $panel1.Name = "panel1"
    #$panel1.BackColor = 'Red'
    $panel1.Dock = 'Fill'
    $splitContainer.Panel1.Controls.Add($panel1)

    $panel2 = New-Object System.Windows.Forms.Panel
    #$panel2.BackColor = 'LightBlue'
    $panel2.Name = "panel2"
    $panel2.Dock = 'Fill'
    $splitContainer.Panel2.Controls.Add($panel2)

    [void]$splitContainer.Handle
    [void]$panel1.Handle 
    [void]$panel2.Handle 

    #region ---------- Content search pattern  ----------------------------
    $lbSearchPattern = New-Object System.Windows.Forms.Label
    $lbSearchPattern.Name = "lbSearchPattern"
    $lbSearchPattern.Text = "Search pattern (regexp)*:"
    $lbSearchPattern.Top = $FIELD_MARGIN_BOTTOM
    $lbSearchPattern.Left = $FORM_PADDING_LEFT
    $lbSearchPattern.Height = $LABEL_HEIGHT
    $lbSearchPattern.Width = $innerWidth
    $lbSearchPattern.Anchor = "Top, Left, Right"
    $lbSearchPattern.AutoEllipsis = $true
    $panel1.Controls.Add($lbSearchPattern)
    
    $txtSearchPattern = New-Object System.Windows.Forms.TextBox
    $txtSearchPattern.Name = "txtSearchPattern"
    $txtSearchPattern.Top = $lbSearchPattern.Bottom
    $txtSearchPattern.Left = $FORM_PADDING_LEFT
    $txtSearchPattern.Height = $panel1.Height - $txtSearchPattern.Top
    $txtSearchPattern.Width = $innerWidth
    $txtSearchPattern.Anchor = "Top, Left, Right, Bottom"
    $txtSearchPattern.Multiline = $true          
    $txtSearchPattern.WordWrap = $true
    $txtSearchPattern.Font = New-Object System.Drawing.Font("Courier New", 9)
    $txtSearchPattern.ScrollBars = "Vertical"

    $txtSearchPattern.Add_KeyPress({
            if ($_.KeyChar -eq "`n" -or $_.KeyChar -eq "`r") { $_.Handled = $true  <#Disable Enter key  #> }
        })

    $txtRegexpTest = New-Object System.Windows.Forms.RichTextBox
    $updateHighlight1 = {
        Start-Debounce -StateObj $txtRegexpTest -DelayMs 100 -Action {
            if ($txtSearchPattern.Text -and (Test-RegexPattern $txtSearchPattern.Text)) {
                $txtSearchPattern.BackColor = [System.Drawing.Color]::White
            }
            else {
                $txtSearchPattern.BackColor = [System.Drawing.Color]::LightCoral
            }
            
            Set-HighlightRegexMatches $txtRegexpTest $txtSearchPattern.Text
        }
    }

    $txtSearchPattern.Add_TextChanged($updateHighlight1)

    $panel1.Controls.Add($txtSearchPattern)
    #endregion

    #region ---------- Regexp test field -------------------------------
    $lbRegexpTest = New-Object System.Windows.Forms.Label
    $lbRegexpTest.Name = "lbRegexpTest"
    $lbRegexpTest.Text = "Pattern test field:"
    $lbRegexpTest.Top = $FIELD_MARGIN_BOTTOM
    $lbRegexpTest.Left = $FORM_PADDING_LEFT
    $lbRegexpTest.Height = $LABEL_HEIGHT
    $lbRegexpTest.Width = $innerWidth
    $lbRegexpTest.Anchor = "Top, Left, Right"
    $lbRegexpTest.AutoEllipsis = $true
    $panel2.Controls.Add($lbRegexpTest)

    $txtRegexpTest.Name = "txtRegexpTest"
    $txtRegexpTest.Top = $lbRegexpTest.Bottom
    $txtRegexpTest.Left = $FORM_PADDING_LEFT
    $txtRegexpTest.Height = $panel2.Height - $txtRegexpTest.Top
    $txtRegexpTest.Width = $innerWidth
    $txtRegexpTest.Anchor = "Top, Bottom, Left, Right"
    $panel2.Controls.Add($txtRegexpTest)

    $updateHighlight2 = {
        Start-Debounce -StateObj $txtRegexpTest -DelayMs 100 -Action {
            Set-HighlightRegexMatches $txtRegexpTest $txtSearchPattern.Text
        }
    }
    $txtRegexpTest.Add_TextChanged($updateHighlight2)
    #endregion
    
    #region ---------- Content search description -------------------------
    $lbSearchDesc = New-Object System.Windows.Forms.Label
    $lbSearchDesc.Name = "lbSearchDesc"
    $lbSearchDesc.Text = "Pattern description:"
    $lbSearchDesc.Top = $splitContainer.Bottom + $FIELD_MARGIN_BOTTOM
    $lbSearchDesc.Left = $FORM_PADDING_LEFT
    $lbSearchDesc.Height = $LABEL_HEIGHT
    $lbSearchDesc.Width = $innerWidth
    $lbSearchDesc.Anchor = "Bottom, Left, Right"
    $lbSearchDesc.AutoEllipsis = $true
    $formChild.Controls.Add($lbSearchDesc)
    
    $txtSearchDesc = New-Object System.Windows.Forms.TextBox
    $txtSearchDesc.Name = "txtSearchDesc"
    $txtSearchDesc.Top = $lbSearchDesc.Bottom
    $txtSearchDesc.Left = $FORM_PADDING_LEFT
    $txtSearchDesc.Height = $FIELD_HEIGHT * 4
    $txtSearchDesc.Width = $innerWidth
    $txtSearchDesc.Anchor = "Bottom, Left, Right"
    $formChild.Controls.Add($txtSearchDesc)
    #endregion

    #region ---------- Content search rules group -------------------------
    $gbPatternLimits = New-Object System.Windows.Forms.GroupBox
    $gbPatternLimits.Name = "gbPatternLimits"
    $gbPatternLimits.Text = "Additional search rules"
    $gbPatternLimits.Top = $txtSearchDesc.Bottom + $FIELD_MARGIN_BOTTOM
    $gbPatternLimits.Left = $FORM_PADDING_LEFT
    $gbPatternLimits.Width = $innerWidth
    $gbPatternLimits.Height = 123
    $gbPatternLimits.Anchor = "Bottom, Left, Right"
    $groupInnerWidth = $gbPatternLimits.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT
    $formChild.Controls.Add($gbPatternLimits)
    #endregion

    #region ---------- Included file msaks ---------------------------
    $lbPatternIncludedFileMasks = New-Object System.Windows.Forms.Label
    $lbPatternIncludedFileMasks.Name = "lbPatternIncludedFileMasks"
    $lbPatternIncludedFileMasks.Top = $FORM_PADDING_TOP
    $lbPatternIncludedFileMasks.Text = "Included file masks:"
    $lbPatternIncludedFileMasks.Left = $FORM_PADDING_LEFT
    $lbPatternIncludedFileMasks.Height = $LABEL_HEIGHT
    $lbPatternIncludedFileMasks.Width = $groupInnerWidth
    $lbPatternIncludedFileMasks.AutoEllipsis = $true
    $lbPatternIncludedFileMasks.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($lbPatternIncludedFileMasks)
    $ttpIncludedFileMasks = New-Object System.Windows.Forms.ToolTip
    $ttpIncludedFileMasks.SetToolTip($lbPatternIncludedFileMasks, "Search pattern will be applied to files with these masks. Empty or '*.*' means all files. For no extension use '*.'")
    $ttpIncludedFileMasks.IsBalloon = $true

    $txtPatternIncludedFileMasks = New-Object System.Windows.Forms.TextBox
    $txtPatternIncludedFileMasks.Name = "txtPatternIncludedFileMasks"
    $txtPatternIncludedFileMasks.Left = $FORM_PADDING_LEFT
    $txtPatternIncludedFileMasks.Top = $lbPatternIncludedFileMasks.Bottom
    $txtPatternIncludedFileMasks.Height = $FIELD_HEIGHT
    $txtPatternIncludedFileMasks.Width = $groupInnerWidth
    $txtPatternIncludedFileMasks.Font = New-Object System.Drawing.Font("Courier New", 9)
    $txtPatternIncludedFileMasks.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($txtPatternIncludedFileMasks)
    #endregion

    #region ---------- Excluded file masks -------------------------------
    $lbPatternExcludedFileMasks = New-Object System.Windows.Forms.Label
    $lbPatternExcludedFileMasks.Name = "lbPatternExcludedFileMasks"
    $lbPatternExcludedFileMasks.Text = "Excluded files masks:"
    $lbPatternExcludedFileMasks.Top = $txtPatternIncludedFileMasks.Bottom + $FIELD_MARGIN_BOTTOM
    $lbPatternExcludedFileMasks.Left = $FORM_PADDING_LEFT
    $lbPatternExcludedFileMasks.Height = $LABEL_HEIGHT
    $lbPatternExcludedFileMasks.Width = $groupInnerWidth - $FIELD_MARGIN_RIGHT - 100
    $lbPatternExcludedFileMasks.Anchor = "Bottom, Left, Right"
    $lbPatternExcludedFileMasks.AutoEllipsis = $true
    $gbPatternLimits.Controls.Add($lbPatternExcludedFileMasks)
    $ttpExcludedFileMasks = New-Object System.Windows.Forms.ToolTip
    $ttpExcludedFileMasks.SetToolTip($lbPatternExcludedFileMasks, "Search pattern will not be applied to files with these masks. Empty means no excluded files.")
    $ttpExcludedFileMasks.IsBalloon = $true

    $txtPatternExcludedFileMasks = New-Object System.Windows.Forms.TextBox
    $txtPatternExcludedFileMasks.Name = "txtPatternExcludedFileMasks"
    $txtPatternExcludedFileMasks.Top = $lbPatternExcludedFileMasks.Bottom
    $txtPatternExcludedFileMasks.Left = $FORM_PADDING_LEFT
    $txtPatternExcludedFileMasks.Height = $FIELD_HEIGHT
    $txtPatternExcludedFileMasks.Width = $groupInnerWidth - $FIELD_MARGIN_RIGHT - 100
    $txtPatternExcludedFileMasks.Font = New-Object System.Drawing.Font("Courier New", 9)
    $txtPatternExcludedFileMasks.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($txtPatternExcludedFileMasks)
    #endregion

    #region ---------- Max content length -------------------------------
    $lbPatternMaxContentLength = New-Object System.Windows.Forms.Label
    $lbPatternMaxContentLength.Name = "lbPatternMaxContentLength"
    $lbPatternMaxContentLength.Text = "Max content length:"
    $lbPatternMaxContentLength.Top = $lbPatternExcludedFileMasks.Top
    $lbPatternMaxContentLength.Left = $lbPatternExcludedFileMasks.Right + $FIELD_MARGIN_RIGHT
    $lbPatternMaxContentLength.Height = $LABEL_HEIGHT
    $lbPatternMaxContentLength.Width = 100
    $lbPatternMaxContentLength.Anchor = "Bottom, Right"
    $lbPatternMaxContentLength.AutoEllipsis = $true
    $gbPatternLimits.Controls.Add($lbPatternMaxContentLength)
    $ttpMaxContentLength = New-Object System.Windows.Forms.ToolTip
    $ttpMaxContentLength.SetToolTip($lbPatternMaxContentLength, "Max content length in chars (not file size). Empty means no limit.")
    $ttpMaxContentLength.IsBalloon = $true

    $txtPatternMaxContentLength = New-Object System.Windows.Forms.TextBox
    $txtPatternMaxContentLength.Name = "txtPatternMaxContentLength"
    $txtPatternMaxContentLength.Top = $lbPatternMaxContentLength.Bottom
    $txtPatternMaxContentLength.Left = $lbPatternMaxContentLength.Left
    $txtPatternMaxContentLength.Height = $FIELD_HEIGHT
    $txtPatternMaxContentLength.Width = 100
    $txtPatternMaxContentLength.Anchor = "Bottom, Right"
    $gbPatternLimits.Controls.Add($txtPatternMaxContentLength)
    #endregion

    #region ---------- Min file size ---------------------------
    $lbPatternMinFileSize = New-Object System.Windows.Forms.Label
    $lbPatternMinFileSize.Name = "lbPatternMinFileSize"
    $lbPatternMinFileSize.Top = $FORM_PADDING_TOP
    $lbPatternMinFileSize.Text = "Min file size:"
    $lbPatternMinFileSize.Left = $FORM_PADDING_LEFT
    $lbPatternMinFileSize.Height = $LABEL_HEIGHT
    $lbPatternMinFileSize.Width = $groupInnerWidth
    $lbPatternMinFileSize.AutoEllipsis = $true
    $lbPatternMinFileSize.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($lbPatternMinFileSize)
    $ttpMinFileSize = New-Object System.Windows.Forms.ToolTip
    $ttpMinFileSize.SetToolTip($lbPatternMinFileSize, "Min file size in bytes. Empty means no limit. Can use Kb, Mb, Gb or just bytes.")
    $ttpMinFileSize.IsBalloon = $true

    $txtPatternMinFileSize = New-Object System.Windows.Forms.TextBox
    $txtPatternMinFileSize.Name = "txtPatternMinFileSize"
    $txtPatternMinFileSize.Left = $FORM_PADDING_LEFT
    $txtPatternMinFileSize.Top = $lbPatternMinFileSize.Bottom
    $txtPatternMinFileSize.Height = $FIELD_HEIGHT
    $txtPatternMinFileSize.Width = $groupInnerWidth
    $txtPatternMinFileSize.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($txtPatternMinFileSize)
    #endregion

    #region ---------- Max file size ---------------------------
    $lbPatternMaxFileSize = New-Object System.Windows.Forms.Label
    $lbPatternMaxFileSize.Name = "lbPatternMaxFileSize"
    $lbPatternMaxFileSize.Top = $txtPatternMinFileSize.Bottom + $FIELD_MARGIN_BOTTOM
    $lbPatternMaxFileSize.Text = "Max file size:"
    $lbPatternMaxFileSize.Left = $FORM_PADDING_LEFT
    $lbPatternMaxFileSize.Height = $LABEL_HEIGHT
    $lbPatternMaxFileSize.Width = $groupInnerWidth
    $lbPatternMaxFileSize.AutoEllipsis = $true
    $lbPatternMaxFileSize.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($lbPatternMaxFileSize)
    $ttpMaxFileSize = New-Object System.Windows.Forms.ToolTip
    $ttpMaxFileSize.SetToolTip($lbPatternMaxFileSize, "Max file size in bytes. Empty means no limit. Can use Kb, Mb, Gb or just bytes.")
    $ttpMaxFileSize.IsBalloon = $true

    $txtPatternMaxFileSize = New-Object System.Windows.Forms.TextBox
    $txtPatternMaxFileSize.Name = "txtPatternMaxFileSize"
    $txtPatternMaxFileSize.Left = $FORM_PADDING_LEFT
    $txtPatternMaxFileSize.Top = $lbPatternMaxFileSize.Bottom
    $txtPatternMaxFileSize.Height = $FIELD_HEIGHT
    $txtPatternMaxFileSize.Width = $groupInnerWidth
    $txtPatternMaxFileSize.Anchor = "Bottom, Left, Right"
    $gbPatternLimits.Controls.Add($txtPatternMaxFileSize)
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

            $validationResult = Test-ValidateSearchPatternForm -modalForm $modalForm
            if (-not $validationResult) { return }

            $data = Get-SearchPatternFormValue -modalForm $modalForm
            if ($null -eq $data) { return }

            if ($mode -eq "add") { $currentRow = $null }
            
            Add-SearchPatternValueToGrid -currentRow $currentRow -data $data | Out-Null
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
        Set-SearchPatternType -modalForm $formChild -type "Content" | Out-Null
    }
    else {
        if (-not $currentRow) { return }
        Set-SearchPatternCurrentRowValue -row $currentRow -modalForm $formChild | Out-Null
    }

    $formChild.ShowDialog($form) 
}

$script:PREV_TEST_FIELD_VALUE = ""
$script:PREV_PATTERN = ""

function Set-HighlightRegexMatches {
    param($richTextBox, $pattern)

    if ($script:PREV_PATTERN -eq $pattern -and $script:PREV_TEST_FIELD_VALUE -eq $richTextBox.Text) { return }
    $script:PREV_PATTERN = $pattern
    $script:PREV_TEST_FIELD_VALUE = $richTextBox.Text

    # Save cursor position
    $selStart = $richTextBox.SelectionStart
    $selLength = $richTextBox.SelectionLength

    $richTextBox.SuspendLayout()
    $richTextBox.HideSelection = $true

    # Reset highlight
    $richTextBox.SelectAll()
    $richTextBox.SelectionBackColor = [System.Drawing.Color]::White

    $resultMatches = Search-ByRegexpPattern -text $richTextBox.Text -pattern $pattern
    if ($resultMatches) { 
        foreach ($m in $resultMatches) {
            $richTextBox.Select($m.Index, $m.Length)
            $richTextBox.SelectionBackColor = [System.Drawing.Color]::Yellow
        }
    }

    # Restore cursor position
    $richTextBox.Select($selStart, $selLength)
    $richTextBox.HideSelection = $false
    $richTextBox.ResumeLayout()
}

function Set-SearchPatternType {
    param (
        [System.Windows.Forms.Form]$modalForm,
        [string]$type
    )

    if ($type -ieq "Content" -or $type -ieq "Filename") { $modalForm.Controls["cmbSearchPatternType"].Text = $type }

    $modalForm.Controls["patternsSplitContainer"].Visible = $type -ieq "Content" -or $type -ieq "Filename"

    $modalForm.Controls["gbPatternLimits"].Controls["lbPatternIncludedFileMasks"].Visible = $type -ieq "Content"
    $modalForm.Controls["gbPatternLimits"].Controls["txtPatternIncludedFileMasks"].Visible = $type -ieq "Content"
    $modalForm.Controls["gbPatternLimits"].Controls["lbPatternExcludedFileMasks"].Visible = $type -ieq "Content"
    $modalForm.Controls["gbPatternLimits"].Controls["txtPatternExcludedFileMasks"].Visible = $type -ieq "Content"
    $modalForm.Controls["gbPatternLimits"].Controls["lbPatternMaxContentLength"].Visible = $type -ieq "Content"
    $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxContentLength"].Visible = $type -ieq "Content"

    
    $modalForm.Controls["gbPatternLimits"].Controls["lbPatternMinFileSize"].Visible = $type -ieq "Filename"
    $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMinFileSize"].Visible = $type -ieq "Filename"
    $modalForm.Controls["gbPatternLimits"].Controls["lbPatternMaxFileSize"].Visible = $type -ieq "Filename"
    $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxFileSize"].Visible = $type -ieq "Filename"
}

function Test-ValidateSearchPatternForm {
    param (
        [System.Windows.Forms.Form]$modalForm
    )

    $type = $modalForm.Controls["cmbSearchPatternType"].SelectedItem

    if ($type -ieq "Content" -Or $type -ieq "Filename") {
        $pattern = $modalForm.Controls["patternsSplitContainer"].Panel1.Controls[0].Controls["txtSearchPattern"].Text.Trim()
        if ([string]::IsNullOrEmpty($pattern)) {
            Show-Error "Regexp pattern is required"
            return $false
        }

        if (-not (Test-RegexPattern $pattern)) { 
            Show-Error "Invalid regexp pattern: $pattern"
            return $false   
        }
    }
    if ($type -ieq "Content") {
        $maxContentLength = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxContentLength"].Text.Trim()

        if ($maxContentLength) {
            $toInt = Convert-ToInt -str $maxContentLength
            if ($null -eq $toInt -or $toInt -lt 0) {
                Show-Error "Invalid max content length: $maxContentLength" 
                return $false
            }
        }

        return $true
    }


    if ($type -ieq "Filename") {
        $minFileSize = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMinFileSize"].Text.Trim()
        $maxFileSize = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxFileSize"].Text.Trim()

        if (-not [string]::IsNullOrEmpty($minFileSize)) {
            $minSize = Convert-ToBytes -size $minFileSize
            if ($null -eq $minSize -or $minSize -lt 0) {
                Show-Error "Invalid Min file size: $minFileSize" 
                return $false
            }
        }

        if (-not [string]::IsNullOrEmpty($maxFileSize)) {
            $maxSize = Convert-ToBytes -size $maxFileSize
            if ($null -eq $maxSize -or $maxSize -lt 0) {
                Show-Error "Invalid Max file size: $maxFileSize" 
                return $false
            }
        }

        return $true
    }

    Show-Error "Invalid search pattern type: $type"

    return $false
}

function Get-SearchPatternFormValue {
    param(
        [System.Windows.Forms.Form]$modalForm
    )

    $type = $modalForm.Controls["cmbSearchPatternType"].SelectedItem

    $data = @{
        Type = $type
    }

    $mode = $modalForm.Tag.mode
    $currentRow = $modalForm.Tag.currentRow
    
    if ($mode -eq "add") { $data.Selected = $true }
    else { $data.Selected = [bool]$currentRow.DataBoundItem["Selected"] }

    if ($type -ieq "Content") {
        $data.Pattern = $modalForm.Controls["patternsSplitContainer"].Panel1.Controls[0].Controls["txtSearchPattern"].Text.Trim()
        $data.Desc = $modalForm.Controls["txtSearchDesc"].Text.Trim()
        $data.IncludedMasks = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternIncludedFileMasks"].Text.Trim()
        $data.ExcludedMasks = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternExcludedFileMasks"].Text.Trim()
        $data.MaxContentLength = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxContentLength"].Text.Trim()
    }
    elseif ($type -ieq "Filename") {
        $data.Pattern = $modalForm.Controls["patternsSplitContainer"].Panel1.Controls[0].Controls["txtSearchPattern"].Text.Trim()
        $data.Desc = $modalForm.Controls["txtSearchDesc"].Text.Trim()
        $data.MinFileSize = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMinFileSize"].Text.Trim()
        $data.MaxFileSize = $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxFileSize"].Text.Trim()
    }
    else {
        return $null
    }

    return $data
}

function Add-SearchPatternValueToGrid {
    param (
        [System.Windows.Forms.DataGridViewRow]$currentRow,
        [hashtable]$data
    )

    $grid = $script:GUI_CONTROLS.gridSearchPatterns

    if (-not $data.ContainsKey("Type") -or -not $data.ContainsKey("Pattern")) { return }

    if (-not $currentRow) { Add-GridRow -grid $grid -values $data -selectAddedRow $true }
    else { Update-GridRow -grid $grid -row $currentRow -values $data }
}

function Set-SearchPatternCurrentRowValue {
    param (
        [System.Windows.Forms.DataGridViewRow]$row,
        [System.Windows.Forms.Form]$modalForm
    )

    if ($null -eq $row) { return $null }

    $type = $row.Cells["Type"].Value
    $pattern = $row.Cells["Pattern"].Value
    $desc = $row.Cells["Desc"].Value
    $includedMasks = $row.Cells["IncludedMasks"].Value
    $excludedMasks = $row.Cells["ExcludedMasks"].Value
    $maxContentLength = $row.Cells["MaxContentLength"].Value
    $minFileSize = $row.Cells["MinFileSize"].Value
    $maxFileSize = $row.Cells["MaxFileSize"].Value

    Set-SearchPatternType -modalForm $modalForm -type $type

    if ($type -ieq "Content") {
        $modalForm.Controls["patternsSplitContainer"].Panel1.Controls[0].Controls["txtSearchPattern"].Text = $pattern
        $modalForm.Controls["txtSearchDesc"].Text = $desc
        $modalForm.Controls["gbPatternLimits"].Controls["txtPatternIncludedFileMasks"].Text = $includedMasks
        $modalForm.Controls["gbPatternLimits"].Controls["txtPatternExcludedFileMasks"].Text = $excludedMasks
        $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxContentLength"].Text = $maxContentLength
    }
    elseif ($type -ieq "Filename") {
        $modalForm.Controls["patternsSplitContainer"].Panel1.Controls[0].Controls["txtSearchPattern"].Text = $pattern
        $modalForm.Controls["txtSearchDesc"].Text = $desc
        $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMinFileSize"].Text = $minFileSize
        $modalForm.Controls["gbPatternLimits"].Controls["txtPatternMaxFileSize"].Text = $maxFileSize
    }

    return $true
}

function Remove-SearchPatternFromGrid {
    $grid = $script:GUI_CONTROLS.gridSearchPatterns
    Remove-SelectedGridRows -grid $grid
}


function Clear-SearchPatternsGrid {
    $grid = $script:GUI_CONTROLS.gridSearchPatterns
    Clear-GridRows -Grid $grid 
}

function Set-SearchPatternsToGrid {
    param (
        [hashtable[]]$searchPatterns
    )

    if (-not $searchPatterns) { 
        Clear-SearchPatternsGrid
        return 
    }

    foreach ($pat in $searchPatterns) {
        Add-SearchPatternValueToGrid -currentRow $null -data $pat
    }


    Set-GridCursorPosition -grid $script:GUI_CONTROLS.gridSearchPatterns -rowIndex 0
}
