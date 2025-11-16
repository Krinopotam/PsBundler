. "$PSScriptRoot/exportCsv.ps1"
. "$PSScriptRoot/importCsv.ps1"

function Initialize-AdvancedGridContextMenu {
    param (
        [System.Windows.Forms.DataGridView]$Grid,
        [System.Windows.Forms.ToolStripItem[]]$ContextMenuItems = @(),
        [string]$DefaulExportFileName
    )
    
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

    foreach ($menuItem in $ContextMenuItems) {
        $contextMenu.Items.Add($menuItem) | Out-Null
    }

    # Export to File context menu item
    $menuItemExportToFile = New-Object System.Windows.Forms.ToolStripMenuItem "Export to file"
    $menuItemExportToFile.Add_Click({
            param($s, $e)

            $menu = $s.Owner  #ContextMenuStrip
            $grid = $menu.SourceControl
            Export-GridToCSV -grid $grid -fileName $grid.Tag.defaulExportFileName | Out-Null
        }) | Out-Null
    $contextMenu.Items.Add($menuItemExportToFile) | Out-Null

    # Import result from File context menu item
    $menuItemImportFromFile = New-Object System.Windows.Forms.ToolStripMenuItem "Import from file"
    $menuItemImportFromFile.Add_Click({ 
            param($s, $e)

            $menu = $s.Owner  #ContextMenuStrip
            $grid = $menu.SourceControl
            Import-GridFromCsvFile -grid $grid | Out-Null
        }) | Out-Null
    $contextMenu.Items.Add($menuItemImportFromFile) | Out-Null

    $grid.ContextMenuStrip = $contextMenu
}
