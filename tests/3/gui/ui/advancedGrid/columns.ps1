function Initialize-AdvancedGridColumns {
    param (
        [System.Windows.Forms.DataGridView]$Grid,
        [System.Windows.Forms.DataGridViewColumn[]]$Columns,
        [string]$CheckboxColumn
    )

    # BindingSource
    $dt = New-Object System.Data.DataTable

    if ($CheckboxColumn) {
        $colCheck = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $colCheck.HeaderText = $CheckboxColumn
        $colCheck.FillWeight = 10
        $colCheck.Tag = @{
            columnName = $CheckboxColumn
            checkState = $null
        }
        $colCheck.Name = $CheckboxColumn
        $colCheck.ValueType = [bool]
        $dt.Columns.Add($CheckboxColumn, [bool]) | Out-Null
        $grid.Columns.Add($colCheck) | Out-Null
    }
        
    foreach ($col in $Columns) {
        $col.DataPropertyName = $col.Name
        $type = [string]
        if ($col.ValueType) { $type = $col.ValueType }
        $dt.Columns.Add($col.Name, $type) | Out-Null 
        $grid.Columns.Add($col) | Out-Null
    }

    $binding = New-Object System.Windows.Forms.BindingSource
    $binding.DataSource = $dt
    $grid.DataSource = $binding
}