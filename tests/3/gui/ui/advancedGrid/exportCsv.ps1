. "$PSScriptRoot/methods.ps1"
. "$PSScriptRoot/../progressBar/progressBar.ps1"
. "$PSScriptRoot/../alerts/alerts.ps1"

# ---------- Export result to CSV file -------------------------
function Export-GridToCsv {
    param (
        [System.Windows.Forms.DataGridView]$grid,
        [string]$fileName = "data.csv"
    )

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv"
    $dialog.FileName = $fileName
    if ($dialog.ShowDialog() -ne 'OK') { return }

    try {
        $pb = Start-ProgressBar -Total $grid.DataSource.Count -Label "Saving..." -canStop $true
        $gridData = Convert-GridDataViewToObject -grid $grid -pb $pb

        if ($gridData -is [bool] -and $gridData -eq $false) { 
            $pb.Close()
            return 
        }

        $gridData | Export-Csv -Path $dialog.FileName -Encoding UTF8 -NoTypeInformation -Delimiter ";"
        $pb.Close()

        Show-Info "File saved: $($dialog.FileName)"
    }
    catch {
        $pb.Close()
        Show-Error "CSV export error:`n$($_.Exception.Message)"
    }
}