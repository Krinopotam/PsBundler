
function Initialize-AdvancedGridCheckboxes {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [string]$checkboxColumn
    )

    if (-not $checkboxColumn) { return }

    $grid.add_CellPainting({
            param($s, $e)

            if ($e.ColumnIndex -ne -0) { return }
            $col = $s.Columns[$e.ColumnIndex]
            $checkName = $col.Tag.columnName   

            $e.PaintBackground($e.ClipBounds, $true)
                
            $state = $false

            if ($e.RowIndex -eq -1) { 
                $allChecked = $true
                $allUnchecked = $true
                $dt = $s.DataSource.DataSource
                foreach ($dr in $dt.Rows) {
                    if ($dr[$checkName] -eq $true) { $allUnchecked = $false }
                    else { $allChecked = $false }
                }

                if ($allChecked) { $state = $true }
                elseif ($allUnchecked) { $state = $false }
                else { $state = $null }
                $col.Tag.checkState = $state 
            }
            else { 
                $val = $s.Rows[$e.RowIndex].DataBoundItem[$checkName]
                if (-not [System.DBNull]::Value.Equals($val)) { $state = [bool]$val } else { $state = $false }
            }

            $buttonState = [Windows.Forms.ButtonState]::Normal 
            if ($state) { $buttonState = [Windows.Forms.ButtonState]::Checked }
            
            $cbSize = 14
            $cbX = $e.CellBounds.X + ($e.CellBounds.Width - $cbSize) / 2
            $cbY = $e.CellBounds.Y + ($e.CellBounds.Height - $cbSize) / 2
            $rect = New-Object Drawing.Rectangle([int]$cbX, [int]$cbY, $cbSize, $cbSize)

            [Windows.Forms.ControlPaint]::DrawCheckBox($e.Graphics, $rect, $buttonState)

            if ($null -eq $state) {
                $inner = $rect
                $inner.Inflate(-3, -3)
                $e.Graphics.FillRectangle([Drawing.Brushes]::Gray, $inner)
            }

            $e.Handled = $true
        })

    $grid.add_CellClick({
            param($s, $e)
            
            if ($e.ColumnIndex -ne -0) { return }

            $col = $s.Columns[$e.ColumnIndex]
            $checkName = $col.Tag.columnName
            $dt = $s.DataSource.DataSource

            $state = $false

            if ($e.RowIndex -eq -1) {
                # Header click
                $state = $col.Tag.checkState
                $newState = -not $state
                $col.Tag.checkState = $newState
                foreach ($r in $dt.rows) {
                    $r[$checkName] = $newState
                } 

                $s.Invalidate()
            }
            else {
                # Row click
                $rowView = $s.Rows[$e.RowIndex].DataBoundItem
                $val = $rowView[$checkName]
                if (-not [System.DBNull]::Value.Equals($val)) { $state = [bool]$val } else { $state = $false }
                $rowView[$checkName] = -not $state
                $s.InvalidateCell($e.ColumnIndex, -1)
            }

            $s.InvalidateCell($e.ColumnIndex, $e.RowIndex)
        })

    $grid.add_RowPrePaint({
            param($s, $e)

            $col = $s.Columns[0]
            $checkName = $col.Tag.columnName
            $rowView = $s.Rows[$e.RowIndex].DataBoundItem
            $val = $rowView[$checkName]
            $state = $false
            if (-not [System.DBNull]::Value.Equals($val)) { $state = [bool]$val } else { $state = $false }
            
            if (-not $state) { $s.Rows[$e.RowIndex].DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gray }
            else { $s.Rows[$e.RowIndex].DefaultCellStyle.ForeColor = [System.Drawing.SystemColors]::WindowText }
        })


}