# Convert Grid DataTable to Object (DataTable includes all rows, no matter if filtered or not)
function Convert-GridDataTableToObject {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [psobject]$pb
    )

    $dt = $grid.DataSource.DataSource
    return Convert-GridRowsToObject -grid $grid -rows $dt.Rows -pb $pb
}

# Conert Grid DataView to Object (DataView includes filtered rows only)
function Convert-GridDataViewToObject {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [psobject]$pb
    )

    $dataView = $grid.DataSource
    return Convert-GridRowsToObject -grid $grid -rows $dataView -pb $pb
}

function Convert-GridRowsToObject {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [System.Object[]]$rows,
        [psobject]$pb
    )

    $result = New-Object object[] $rows.Count #new fixed array
    $rowIdx = 0
    foreach ($row in $rows) {
        $result[$rowIdx] = Convert-GridRowToObject -row $row -columns $grid.Columns
        $rowIdx++
    
        if (-not $pb) { continue }
        $pb.Update($rowIdx)
        if ($pb.IsCanceled) { return $false }
    }

    if ($rowIdx -gt 0) { return $result[0..($rowIdx - 1)] }
    else { return ,@() }
}

function Convert-GridRowToObject {
    param (
        [System.Object]$row,
        [System.Windows.Forms.DataGridViewColumnCollection]$columns
    )

    $obj = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($col in $columns) {
        $value = $row[$col.Name]
        if ($col.ValueType -eq [datetime] -and $value -ne [DBNull]::Value) { $value = $value.ToString("yyyy-MM-dd HH:mm:ss") }
        $obj.Add($col.HeaderText, $value)
    }
    return New-Object PSObject -Property $obj 
}

# Returns grid full data as Hashtables array
function Get-AdvancedGridDataHashtables {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [string]$filterColumn = $null
    )

    $dt = $grid.DataSource.DataSource

    $result = New-Object object[] $dt.Rows.Count #new fixed array
    $rowIdx = 0

    foreach ($row in $dt.Rows) {
        if ($filterColumn -and ([DBNull]::Value.Equals($row[$filterColumn]) -or -not $row[$filterColumn])) { continue }

        $rowObj = @{}
        $hasVal = $false
        foreach ($col in $dt.Columns) { 
            $val = $row[$col.ColumnName]
            if ([DBNull]::Value.Equals($val)) { $val = $null }
            if ($val) { $hasVal = $true }
            $rowObj[$col.ColumnName] = $val
        }

        if ($hasVal) {
            $result[$rowIdx] = $rowObj
            $rowIdx++
        }
    }

    if ($rowIdx -gt 0) { return $result[0..($rowIdx - 1)] }
    else { return  ,@() }
}

# Add new DataRow to grid DataTable
function Add-GridRowToDataTable {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Collections.Hashtable]$values
    )

    $hasCells = $false

    $dt = $grid.DataSource.DataSource
    $row = $dt.NewRow()
    foreach ($col in $dt.Columns) {
        if (-not $values.ContainsKey($col.ColumnName)) { continue }
        $hasCells = $true
        $row[$col.ColumnName] = $values[$col.ColumnName]
            
    }
    if ($hasCells) { 
        [void]$dt.Rows.Add($row) 
        return $true
    }

    return $false
}

# Add new DataViewRow to grid BindingSource (DataView)
function Add-GridRowToBindingSource {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Collections.Hashtable]$values
    )

    $hasCells = $false

    $bs = $grid.DataSource
    $dt = $bs.DataSource
    $drv = $bs.AddNew()  # create DataRowView

    foreach ($col in $dt.Columns) {
        if (-not $values.ContainsKey($col.ColumnName)) { continue }
        $hasCells = $true
        $drv[$col.ColumnName] = $values[$col.ColumnName]
    }

    if (-not $hasCells) { 
        $bs.CancelEdit()
        return $false 
    }

    $bs.EndEdit()
    
    return $true
}

function Add-GridRow {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Collections.Hashtable]$values,
        [boolean]$selectAddedRow
    )

    if (-not $selectAddedRow) { return Add-GridRowToDataTable -grid $grid -values $values }
    else { return Add-GridRowToBindingSource -grid $grid -values $values }
}

function Update-GridRow {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Windows.Forms.DataGridViewRow]$row,
        [System.Collections.Hashtable]$values
    )

    if (-not $row -or -not $row.DataBoundItem) { return }

    $drv = $row.DataBoundItem
    $dt = $grid.DataSource.DataSource

    $drv.BeginEdit()
    foreach ($col in $dt.Columns) {
        if (-not $values.ContainsKey($col.ColumnName) -or $null -eq $values[$col.ColumnName]) { 
            if ($col.DataType -eq [string]) { $drv[$col.ColumnName] = $null }
            else { $drv[$col.ColumnName] = [DBNull]::Value }
        }
        else { $drv[$col.ColumnName] = $values[$col.ColumnName] }
    }
    $drv.EndEdit()
}

function Remove-GridRow {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [System.Windows.Forms.DataGridViewRow]$row
    )

    if (-not $row -or -not $row.DataBoundItem) { return }
    
    $bs = $grid.DataSource
    $drv = $row.DataBoundItem
    [void]$bs.Remove($drv)
    
}

function Remove-SelectedGridRows {
    param(
        [System.Windows.Forms.DataGridView]$grid
    )

    $rows = $grid.SelectedRows

    $dt = $grid.DataSource.DataSource
    if ($rows.Count -eq $dt.Rows.Count) {
        $grid.SuspendLayout()
        $dt.Rows.Clear()
        $grid.ResumeLayout()
        return
    }

    foreach ($row in $rows) {
        if ($row.IsNewRow) { continue }
        Remove-GridRow -grid $grid -row $row | Out-Null
    }
}   

function Clear-GridRows {
    param(
        [System.Windows.Forms.DataGridView]$Grid
    )
    
    $dt = $Grid.DataSource.DataSource
    [void]$dt.Rows.Clear()
}

# return full rows count in dataTable (no matter if filtered or not)
function Get-FullRowsCount {
    param (
        [System.Windows.Forms.DataGridView]$grid
    )
    
    $dt = $grid.DataSource.DataSource
    return $dt.Rows.Count
}

function Set-GridCursorPosition {
    param(
        [System.Windows.Forms.DataGridView]$grid,
        [int]$rowIndex = 0,
        [int]$colIndex = 0
    )

    if ($rowIndex -lt 0 -or $rowIndex -ge $grid.Rows.Count) { return }
    if ($colIndex -lt 0 -or $colIndex -ge $grid.Columns.Count) { return }

    $grid.ClearSelection()
    $grid.CurrentCell = $grid.Rows[$rowIndex].Cells[$colIndex]
}
