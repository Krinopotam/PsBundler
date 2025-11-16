. "$PSScriptRoot/../../debounce.ps1"

# Init Search textBox panel
function Initialize-GridSearchPanel {
    param(
        [System.Windows.Forms.Control]$container,    
        [System.Windows.Forms.DataGridView]$grid
    )

    $panelSearch = New-Object System.Windows.Forms.Panel

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Name = "txtSearch"
    $txtSearch.Width = 100
    $txtSearch.Left = 3
    $txtSearch.BackColor = [System.Drawing.Color]::LemonChiffon
    $txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtSearch.Tag = $grid

    $prevButton = New-Object System.Windows.Forms.Button
    $prevButton.Text = "<"
    $prevButton.Width = $txtSearch.Height
    $prevButton.Height = $txtSearch.Height
    $prevButton.Left = $txtSearch.Right + 3
    $prevButton.Top = $txtSearch.Top
    $prevButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $prevButton.FlatAppearance.BorderSize = 0
    $prevButton.Tag = $grid
    $prevButton.Add_Click({ 
            param($s, $e)
            $txtSearch = $s.Parent.Controls["txtSearch"]
            $txtSearch.Focus()
            Search-AdvancedGridValue -txtFilter $txtSearch -direction "Prev" | Out-Null
        })
    $panelSearch.Controls.Add($prevButton) | Out-Null
    
    $nextButton = New-Object System.Windows.Forms.Button
    $nextButton.Text = ">"
    $nextButton.Width = $txtSearch.Height
    $nextButton.Height = $txtSearch.Height
    $nextButton.Left = $prevButton.Right
    $nextButton.Top = $txtSearch.Top
    $nextButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $nextButton.FlatAppearance.BorderSize = 0
    $nextButton.Tag = $grid
    $nextButton.Add_Click({ 
            param($s, $e)
            $txtSearch = $s.Parent.Controls["txtSearch"]
            $txtSearch.Focus()
            Search-AdvancedGridValue -txtFilter $txtSearch -direction "Next" | Out-Null
        })
    $panelSearch.Controls.Add($nextButton) | Out-Null

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "X"
    $closeButton.Width = $txtSearch.Height
    $closeButton.Height = $txtSearch.Height
    $closeButton.Left = $nextButton.Right
    $closeButton.Top = $txtSearch.Top
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.Tag = $grid
    $closeButton.Add_Click({ 
            param($s, $e)
            $s.Parent.Visible = $false
            $s.Parent.Controls["txtSearch"].Text = "" 
            $grid = $s.Tag
            Set-AdvancedGridCellHighlight -grid $grid -cell $null | Out-Null
            $grid.Focus()
        })
    $panelSearch.Controls.Add($closeButton) | Out-Null

    $panelSearch.Height = $txtSearch.Height
    $panelSearch.Width = $closeButton.Right
    $panelSearch.BackColor = $txtSearch.BackColor
    $panelSearch.Visible = $false
    $panelSearch.Anchor = "Top,Right"
    $panelSearch.Top = $grid.Top + 3
    $panelSearch.Left = $grid.Right - $panelSearch.Width - 3
    $panelSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panelSearch.Controls.Add($txtSearch) | Out-Null
    
    $container.Controls.Add($panelSearch) | Out-Null
    $panelSearch.BringToFront() | Out-Null

    $grid.Tag.panelSearch = $panelSearch
    $grid.Tag.txtSearch = $txtSearch
        

    $txtSearch.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { 
                $s.Parent.Visible = $false
                $s.Text = "" 
                $grid = $s.Tag
                Set-AdvancedGridCellHighlight -grid $grid -cell $null | Out-Null
                $grid.Focus()
            }
            elseif (($e.KeyCode -eq [System.Windows.Forms.Keys]::F3 -or $e.KeyCode -eq ([System.Windows.Forms.Keys]::Enter)) -and -not $e.Control) {
                $direction = if ($e.Shift) { "Prev" } else { "Next" }
                Search-AdvancedGridValue -txtFilter $s -direction $direction | Out-Null
            }
        }) | Out-Null

    $txtSearch.Add_TextChanged({
            param($s, $e)
            Start-Debounce -StateObj $s -Action { param($ctrl) Search-AdvancedGridValue -txtFilter $ctrl }
        }) | Out-Null 

}

function Search-AdvancedGridValue {
    param(
        [System.Windows.Forms.TextBox]$txtFilter,
        [string]$direction = $null
    )

    $grid = $txtFilter.Tag

    $value = $txtFilter.Text
    if (-not  $value) { 
        Set-AdvancedGridCellHighlight -grid $grid -cell $null | Out-Null
        return 
    }

    $rowCount = $grid.Rows.Count
    $colCount = $grid.Columns.Count
    if ($rowCount -eq 0 -or $colCount -eq 0) { return }

    # Found start position
    $startRow = 0
    $startCol = 0
    if ($grid.CurrentCell) {
        $startRow = $grid.CurrentCell.RowIndex
        $startCol = $grid.CurrentCell.ColumnIndex
    }

    $row = $startRow
    $col = $startCol

    do {
        if (-not $direction -or $row -ne $startRow -or $col -ne $startCol) {
            $res = Search-AdvancedGridCellValue -grid $grid -rowIndex $row -colIndex $col -value $value
            if ($res) { return }
        }

        # Move position
        if ($direction -eq "Prev") {
            $col--
            if ($col -lt 0) {
                $col = $colCount - 1
                $row--
                if ($row -lt 0) { $row = $rowCount - 1 }
            }
        }
        else {
            $col++
            if ($col -ge $colCount) {
                $col = 0
                $row++
                if ($row -ge $rowCount) { $row = 0 }
            }
        }

    } while ($row -ne $startRow -or $col -ne $startCol)

    if ($direction -and (Search-AdvancedGridCellValue -grid $grid -rowIndex $row -colIndex $col -value $value)) { return }

    Set-AdvancedGridCellHighlight -grid $grid -cell $null | Out-Null
}

function Search-AdvancedGridCellValue {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [int]$rowIndex,
        [int]$colIndex,
        [string]$value
    )
    
    $dgRow = $grid.Rows[$rowIndex]
    if (-not $dgRow.Visible) { return $false }
    
    $cell = $dgRow.Cells[$colIndex]
    if ($cell.Visible -and $null -ne $cell.FormattedValue -and ($cell.FormattedValue.ToString() -like "*$value*")) {
        $grid.CurrentCell = $cell
        Set-AdvancedGridCellHighlight -grid $grid -cell $cell | Out-Null
        return $true
    }

    return $false
}

function Set-AdvancedGridCellHighlight {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Windows.Forms.DataGridViewCell]$cell
    )

    if ($grid.Tag.lastHighlightedCell) {
        $grid.Tag.lastHighlightedCell.Style.BackColor = $grid.Tag.lastHighlightedCellOriginalStyle.BackColor
        $grid.Tag.lastHighlightedCell.Style.ForeColor = $grid.Tag.lastHighlightedCellOriginalStyle.ForeColor
        $grid.Tag.lastHighlightedCell.Style.SelectionBackColor = $grid.Tag.lastHighlightedCellOriginalStyle.SelectionBackColor
        $grid.Tag.lastHighlightedCell.Style.SelectionForeColor = $grid.Tag.lastHighlightedCellOriginalStyle.SelectionForeColor
    }

    if (-not $cell) { 
        $grid.Tag.lastHighlightedCell = $null
        return 
    }

    $grid.Tag.lastHighlightedCellOriginalStyle = @{
        BackColor          = $cell.Style.BackColor
        ForeColor          = $cell.Style.ForeColor
        SelectionBackColor = $cell.Style.SelectionBackColor
        SelectionForeColor = $cell.Style.SelectionForeColor
    }

    $cell.Style.BackColor = [System.Drawing.Color]::Orange
    $cell.Style.ForeColor = [System.Drawing.Color]::Black
    $cell.Style.SelectionBackColor = [System.Drawing.Color]::Orange
    $cell.Style.SelectionForeColor = [System.Drawing.Color]::Black

    $grid.Tag.lastHighlightedCell = $cell
}

