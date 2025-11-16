. "$PSScriptRoot/buttons.ps1"
. "$PSScriptRoot/columns.ps1"
. "$PSScriptRoot/contextMenu.ps1"
. "$PSScriptRoot/search.ps1"
. "$PSScriptRoot/filter.ps1"
. "$PSScriptRoot/methods.ps1"
. "$PSScriptRoot/checkboxes.ps1"
. "$PSScriptRoot/../progressBar/progressBar.ps1"
. "$PSScriptRoot/../alerts/alerts.ps1"
. "$PSScriptRoot/../../../helpers/strings.ps1"

function Initialize-AdvancedGrid {
    param (
        [System.Windows.Forms.Control]$container,
        [int]$PaddingTop = 0,
        [int]$PaddingBottom = 0,
        [int]$PaddingLeft = 0,
        [int]$PaddingRight = 0,
        [int]$height = 0,
        [int]$width = 0,
        [hashtable[]]$Buttons = @(),
        [string]$HeaderLabelText = "",
        [string]$HeaderLabelTooltip = "",
        [int]$HeaderLabelHeight = 20,
        [int]$HeaderLabelWidth = 0,

        [System.Windows.Forms.DataGridViewColumn[]]$Columns = @(),
        [boolean]$ReadOnly = $true,
        [System.Windows.Forms.DataGridViewSelectionMode]$SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect,
        [boolean]$MultiSelect = $false,
        [string]$CheckboxColumn = $null,
        [System.Windows.Forms.DataGridViewAutoSizeRowsMode]$AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::DisplayedCells,
        [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]$AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill,
        [string]$Anchor = "Top, Left, Right, Bottom",
        [System.Windows.Forms.ToolStripItem[]]$ContextMenuItems = @(),
        [boolean]$RowHeadersVisible = $false,
        [string]$DefaulExportFileName = "export.csv",

        [ScriptBlock]$OnKeyDown = $null,
        [ScriptBlock]$OnPreviewKeyDown = $null,
        [ScriptBlock]$OnKeyPress = $null,
        [ScriptBlock]$OnCellClick = $null,
        [ScriptBlock]$OnCellDoubleClick = $null
    )

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Tag = @{
        defaulExportFileName             = $DefaulExportFileName
        onKeyDown                        = $OnKeyDown
        onPreviewKeyDown                 = $OnPreviewKeyDown
        onKeyPress                       = $OnKeyPress
        onCellClick                      = $OnCellClick
        onCellDoubleClick                = $OnCellDoubleClick
        lbGridHeader                     = $null
        lastHighlightedCell              = $null
        lastHighlightedCellOriginalStyle = $null
    }

    $containerInnerWidth = $Container.ClientSize.Width - $FORM_PADDING_LEFT - $FORM_PADDING_RIGHT

    $gridTop = $PaddingTop
    if ($headerLabelText) {
        $lbGridHeader = New-Object System.Windows.Forms.Label
        $lbGridHeader.Text = $HeaderLabelText
        $lbGridHeader.Top = $PaddingTop
        $lbGridHeader.Left = $PaddingLeft
        $lbGridHeader.Height = $HeaderLabelHeight
        $lbGridHeader.Width = if ($HeaderLabelWidth) { $HeaderLabelWidth } else { $containerInnerWidth }
        $lbGridHeader.Anchor = "Top, Left"
        $grid.Tag.lbGridHeader = $lbGridHeader
        $container.Controls.Add($lbGridHeader) | Out-Null
        $gridTop = $lbGridHeader.Bottom

        if ($HeaderLabelTooltip) {
            $ttpHeaderLabel = New-Object System.Windows.Forms.ToolTip
            $ttpHeaderLabel.SetToolTip($lbGridHeader, $HeaderLabelTooltip)
            $ttpHeaderLabel.IsBalloon = $true
        }
    }

    Initialize-AdvancedGridButtons -Container $container -Buttons $Buttons -PaddingRight $PaddingRight -PaddingTop $PaddingTop | Out-Null

    $grid.AutoGenerateColumns = $false

    $grid.Top = $gridTop
    $grid.Left = $PaddingLeft
    $grid.Height = if ($Height) { $height } else { $Container.ClientSize.Height - $gridTop - $PaddingBottom }
    $grid.Width = if ($width) { $width } else { $containerInnerWidth }
    $grid.ReadOnly = $ReadOnly
    $grid.SelectionMode = $SelectionMode
    $grid.MultiSelect = $MultiSelect
    $grid.AllowUserToAddRows = $false
    $grid.AutoSizeRowsMode = $AutoSizeRowsMode
    $grid.AutoSizeColumnsMode = $AutoSizeColumnsMode
    $grid.Anchor = $Anchor
    $grid.RowHeadersVisible = $RowHeadersVisible
    $grid.Add_KeyDown({
            param($s, $e)

            if ($s.Tag.onKeyDown) {
                $cont = & $s.Tag.onKeyDown $s $e
                if ($cont -is [bool] -and $cont -eq $false) { return }
            }

            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Back) {
                $txtFilter = $s.Tag.txtFilter
                if ($txtFilter.Text.Length -le 0) { return }
                
                $txtFilter.Text = $txtFilter.Text.Substring(0, $txtFilter.Text.Length - 1)
                $txtFilter.SelectionStart = $txtFilter.Text.Length
                $txtFilter.SelectionLength = 0
                
            }
            elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { 
                $panelSearch = $s.Tag.panelSearch
                $txtSearch = $s.Tag.txtSearch
                if ($panelSearch.Visible) {
                    $panelSearch.Visible = $false
                    $txtSearch.Text = ""
                    $grid = $txtSearch.Tag
                    Set-AdvancedGridCellHighlight -grid $grid -cell $null | Out-Null
                    return
                }

                $txtFilter = $s.Tag.txtFilter
                $txtFilter.Text = ""
            }
            elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
                $panelSearch = $s.Tag.panelSearch
                $txtSearch = $s.Tag.txtSearch
                
                if ($panelSearch.Visible) {
                    $panelSearch.Visible = $false
                    $txtSearch.Text = ""
                    return
                }
                
                $panelSearch.Visible = $true
                $txtSearch.Focus()      
            }
            elseif ($e.KeyCode -eq 'Delete' -and -not $e.Control -and -not $e.Alt -and -not $e.Shift) {
                $dt = $s.DataSource.DataSource
                if ($s.SelectedRows.Count -eq $dt.Rows.Count) {
                    # DGV deleting is too slow. Clear the whole table if deleting all rows, it's much faster
                    $dt.Rows.Clear()
                    $e.SuppressKeyPress = $true
                    return
                }
            } 
        }) | Out-Null

    $grid.Add_KeyPress({
            param($s, $e)

            if ($s.Tag.onKeyPress) {
                $cont = & $s.Tag.onKeyPress $s $e
                if ($cont -is [bool] -and $cont -eq $false) { return }
            }
            
            if ([char]::IsControl($e.KeyChar)) { return }

            $txtFilter = $s.Tag.txtFilter
            $txtFilter.Text += $e.KeyChar

            # Set the cursor to the end
            $txtFilter.SelectionStart = $txtFilter.Text.Length
            $txtFilter.SelectionLength = 0
        }) | Out-Null
    
    $grid.Add_PreviewKeyDown({
            param($s, $e)
            if ($s.Tag.onPreviewKeyDown) { & $s.Tag.onPreviewKeyDown $s $e }
        })

    $grid.Add_CellClick({
            param($s, $e)
            if ($s.Tag.onCellClick) { & $s.Tag.onCellClick $s $e }
        }) | Out-Null
    
    $grid.Add_CellDoubleClick({
            param($s, $e)
            if ($s.Tag.onCellDoubleClick) { & $s.Tag.onCellDoubleClick $s $e }
        }) | Out-Null

    $grid.Add_MouseDown({
            param($s, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $hit = $s.HitTest($e.X, $e.Y)
                if ($hit.RowIndex -lt 0) { return }
                
                $row = $s.Rows[$hit.RowIndex]
                if ($row.Selected) { return }

                $s.ClearSelection()
                $row.Selected = $true
                $s.CurrentCell = $row.Cells[0]
             }
        })

    Initialize-AdvancedGridCheckboxes -Grid $grid -checkboxColumn $CheckboxColumn | Out-Null
    Initialize-AdvancedGridColumns -Grid $grid -Columns $Columns -CheckboxColumn $CheckboxColumn | Out-Null
    Initialize-AdvancedGridContextMenu -Grid $grid -ContextMenuItems $ContextMenuItems -DefaulExportFileName $DefaulExportFileName | Out-Null

    $container.Controls.Add($grid) | Out-Null

    Initialize-GridFilterPanel -container $container -Grid $grid | Out-Null
    Initialize-GridSearchPanel -container $container -Grid $grid | Out-Null
   
    return $grid
}

