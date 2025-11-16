. "$PSScriptRoot/methods.ps1"
. "$PSScriptRoot/../progressBar/progressBar.ps1"
. "$PSScriptRoot/../alerts/alerts.ps1"

# ---------- Import result from CSV file ----------------------
function Import-GridFromCsvFile {
    param (
        [System.Windows.Forms.DataGridView]$grid
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv"
    if ($dialog.ShowDialog() -ne 'OK') { return }
    
    $clearGrid = $false
    if ((Get-FullRowsCount -grid $grid) -gt 0) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Do you want to clear the grid before importing?",
            "Import Options",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq 'Yes') { $clearGrid = $true }
    }

    try {
        $data = @(Import-Csv -Path $dialog.FileName -Delimiter ";") #wrap in array because Import-Csv returns PSCustomObject for single row and array for multiple

        if ($data.Count -eq 0) {
            Show-Info "File is empty"      
            return
        }

        $pb = Start-ProgressBar -Total $data.Count -Label "Importing..." -canStop $true 
        $importedCount = Import-GridFromCsvData -grid $grid -data $data -clearGrid $clearGrid -pb $pb
        $pb.Close()

        if ($importedCount -is [bool] -and $importedCount -eq $false) { return }

        if (-not $importedCount) {
            Show-Info "No data was imported"
            return
        }

        Show-Info "Imported $importedCount rows from file: $($dialog.FileName)"
    }
    catch {
        $grid.ResumeLayout()
        Show-Error "CSV export error:`n$($_.Exception.Message)"
    }
}

function Import-GridFromCsvData {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [object[]]$data,
        [boolean]$clearGrid = $false,
        [psobject]$pb
    )

    if ($clearGrid) { Clear-GridRows -grid $grid | Out-Null }

    if (-not $data -or $data.Count -eq 0) { return 0 }

    #WORKAROUND: In PS 2 $csvColumns = $data[0].PSObject.Properties.Name does not work
    $csvColumns = @( $data[0] | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name.ToLower() } )

    # Create columns a map: column header name => grid column name
    $columnMap = @{}
    $typesMap = @{}
    for ($i = 0; $i -lt $grid.Columns.Count; $i++) {
        $headerName = [string]$grid.Columns[$i].HeaderText.ToLower()
        if ($csvColumns -contains $headerName) { 
            $columnMap[$headerName] = $grid.Columns[$i].Name 
            $typesMap[$grid.Columns[$i].Name ] = $grid.Columns[$i].ValueType
        }
    }

    $dtNew = $grid.DataSource.DataSource.Copy()

    $rowsCount = 0
    $importedCount = 0

    foreach ($row in $data) {
        $rowsCount++

        $newRow = $dtNew.NewRow()
    
        $allEmpty = $true
        $cells = $row.PSObject.Properties
        foreach ($cell in $cells) {
            $cellName = $cell.name.ToLower()
            if (-not $columnMap.ContainsKey($cellName)) { continue }
            $colName = $columnMap[$cellName]
            $colType = $typesMap[$colName]

            $value = $cell.value

            if ($null -eq $value) { $value = [System.DBNull]::Value }
            else {
                try {
                    if ($colType -eq [datetime]) { $value = [datetime]::Parse($value) } # GPT says that ChangeType sometimes fails date parsing when date like 2025-10-10 12:00:00
                    elseif ($colType -ne [string]) { $value = [System.Convert]::ChangeType($value, $colType) }
                }
                catch { $value = [System.DBNull]::Value }
            }

            $newRow[$colName] = $value
            if (-not [System.DBNull]::Value.Equals($value)) { $allEmpty = $false }
        } 

        if (-not $allEmpty) {
            $dtNew.Rows.Add($newRow)
            $importedCount++
        }

        if (-not $pb) { continue }
        $pb.Update($rowsCount)
        if ($pb.IsCanceled) { return $false }
    }

    $grid.DataSource.DataSource = $dtNew
    return $importedCount
}