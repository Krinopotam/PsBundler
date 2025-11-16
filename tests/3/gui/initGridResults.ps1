. "$PSScriptRoot/ui/advancedGrid/advancedGrid.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"
. "$PSScriptRoot/ui/alerts/alerts.ps1"
. "$PSScriptRoot/ui/progressBar/progressBar.ps1"
. "$PSScriptRoot/formConstants.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/../helpers/forms.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/../helpers/objects.ps1"

$script:TEMP_FILE_PATH_TO_OPEN = ""

function Initialize-GridResults {
    param (
        [System.Windows.Forms.Form]$form,
        [System.Windows.Forms.Control]$container
    )


    $columns = Get-GridResultsColumns
    $contextMenuItems = Get-GridResultsContextMenu

    $onCellDoubleClick = {
        param($s, $e)

        $form = $script:GUI_CONTROLS.form
        $rowIndex = $e.RowIndex
        if ($rowIndex -ge 0) {
            $row = $s.Rows[$rowIndex]
            $script:TEMP_FILE_PATH_TO_OPEN = $row.Cells["FilePath"].Value

            # Run on UI thread after event to prevent DataGridView glitches
            $null = $form.BeginInvoke([System.Windows.Forms.MethodInvoker] {
                    Open-FileView $script:TEMP_FILE_PATH_TO_OPEN
                })
        }
    }

    $onKeyDown = {
        param($s, $e)
        
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            if (-not $e.Shift -and -not $e.Control) { Open-GridResultFiles -grid $s | Out-Null } 
            elseif ($e.Shift -and -not $e.Control) { Open-GridResultFileFolders -grid $s | Out-Null }
            $e.SuppressKeyPress = $true
        }
    }

    $grid = Initialize-AdvancedGrid `
        -Container $container `
        -Columns $columns `
        -HeaderLabelHeight $LABEL_HEIGHT `
        -PaddingTop $FORM_PADDING_TOP `
        -PaddingBottom $FORM_PADDING_BOTTOM `
        -PaddingLeft $FORM_PADDING_LEFT `
        -PaddingRight $FORM_PADDING_RIGHT `
        -HeaderLabelText "Results:" `
        -MultiSelect $true `
        -ContextMenuItems $contextMenuItems `
        -DefaulExportFileName "results.csv" `
        -OnKeyDown $onKeyDown `
        -OnCellDoubleClick $onCellDoubleClick

    $script:GUI_CONTROLS.gridResults = $grid
}

function Get-GridResultsColumns {
    $colNum = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colNum.Name = "#"
    $colNum.HeaderText = "#"
    $colNum.ValueType = [long]
    $colNum.FillWeight = 10

    $colFilePath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colFilePath.Name = "FilePath"
    $colFilePath.HeaderText = "File Path"
    $colFilePath.FillWeight = 130
    $colFilePath.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colFileSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colFileSize.Name = "FileSize"
    $colFileSize.HeaderText = "Size"
    $colFileSize.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $colFileSize.ValueType = [long]
    $colFileSize.DefaultCellStyle.Format = "N0"
    $colFileSize.FillWeight = 20

    $colFileDate = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colFileDate.Name = "FileDate"
    $colFileDate.HeaderText = "Date"
    $colFileDate.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
    $colFileDate.ValueType = [datetime]
    $colFileDate.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True
    $colFileDate.DefaultCellStyle.Format = "yyyy-MM-dd HH:mm:ss"
    $colFileDate.FillWeight = 20

    $colContent = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colContent.Name = "Content"
    $colContent.HeaderText = "Content"
    $colContent.FillWeight = 70
    $colContent.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $colRuleDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colRuleDesc.Name = "RuleDesc"
    $colRuleDesc.HeaderText = "Rule"
    $colRuleDesc.FillWeight = 50
    $colRuleDesc.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    return @($colNum, $colFilePath, $colFileSize, $colFileDate, $colContent, $colRuleDesc)
}

function Get-GridResultsContextMenu {
    # Open File context menu item
    $menuItemOpenFile = New-Object System.Windows.Forms.ToolStripMenuItem "Open File                            ENTER" # Enter can't be used as hot key, so we have to add it manually
    $menuItemOpenFile.Add_Click({ 
            param($s, $e)
            $grid = $script:GUI_CONTROLS.gridResults
            Open-GridResultFiles -grid $grid | Out-Null 
        })

    # Open Folder context menu item
    $menuItemOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem "Open Folder                       SHIFT+ENTER"
    $menuItemOpenFolder.Add_Click({
            param($s, $e)
            $grid = $script:GUI_CONTROLS.gridResults
            Open-GridResultFileFolders -grid $grid | Out-Null
        })

    # Context menu separator
    $separator1 = New-Object System.Windows.Forms.ToolStripSeparator

    # Copy file with full path
    $menuItemCopyFileWithFullPath = New-Object System.Windows.Forms.ToolStripMenuItem "Copy file with full path"
    $menuItemCopyFileWithFullPath.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Shift -bor [System.Windows.Forms.Keys]::S
    $menuItemCopyFileWithFullPath.ShowShortcutKeys = $true
    $menuItemCopyFileWithFullPath.Add_Click({
            param($s, $e)

            $grid = $script:GUI_CONTROLS.gridResults
            $rows = $grid.SelectedRows
            if ($null -eq $rows -or $rows.Count -eq 0) { return }

            $folder = Select-DestinationFolderForCopy
            if (-not $folder) { return }
            
            $files = @(Get-GridResultSelectedUniqueFiles -grid $grid)
            Copy-FilesWithFullPath -Files $files -DestRoot $folder
        })

    # Copy file to clipboartd
    $menuItemClipboardCopy = New-Object System.Windows.Forms.ToolStripMenuItem "Copy file to clipboard"
    $menuItemClipboardCopy.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Shift -bor [System.Windows.Forms.Keys]::C
    $menuItemClipboardCopy.ShowShortcutKeys = $true

    $menuItemClipboardCopy.Add_Click({
            param($s, $e)
            $grid = $script:GUI_CONTROLS.gridResults
            Copy-SelectedFilesToClipboard $grid | Out-Null
        })

    # Context menu separator
    $separator2 = New-Object System.Windows.Forms.ToolStripSeparator

    return @($menuItemOpenFile, $menuItemOpenFolder, $separator1, $menuItemCopyFileWithFullPath, $menuItemClipboardCopy, $separator2)
}

function Copy-SelectedFilesToClipboard {
    param([System.Windows.Forms.DataGridView]$grid)

    $rows = $grid.SelectedRows
    if ($null -eq $rows -or $rows.Count -eq 0) { return }

    $fileList = New-Object System.Collections.Specialized.StringCollection
    foreach ($row in $rows) {
        $filePath = $row.Cells["FilePath"].Value
        if ($fileList.Contains($filePath)) { continue }
        $fileList.Add($filePath)
    }

    Copy-FilesToClipboard $fileList
}

function Copy-FilesWithFullPath {
    param(
        [string[]]$Files,
        [string]$DestRoot
    )

    if ($Files.Count -eq 0) { return }

    $errors = @()
    $total = $files.Count
    $copied = 0
    $current = 0

    $pb = Start-ProgressBar -Total $total -Label "Copying..."
    foreach ($file in $Files) {
        $err = Copy-FileWithFullPath -SourceFile $file -DestRoot $DestRoot
        if (-not $err) {
            $copied++
        }
        else {
            $errors += ($file + " - " + $err)
        }
        
        $current++
        $pb.Update($current)
    }
    $pb.Close()

    
    if ($errors.Count -eq 0) { return }

    $resultMsg = "Copied $copied of $total files to '$DestRoot'"
    $resultMsg += "`r`n`r`nErrors:`r`n`r`n"

    $maxShow = 5
    $shown = @($errors | Select-Object -First $maxShow)
    $resultMsg += ($shown -join "`r`n`r`n")

    if ($errors.Count -gt $maxShow) {
        $more = $errors.Count - $maxShow
        $resultMsg += "`r`n`r`n...and $more more errors"
    }
    
    Show-Info $resultMsg
}

$script:LAST_DESCTINATION_PATH = ""
function Select-DestinationFolderForCopy {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog

    if ($script:LAST_DESCTINATION_PATH -and (Test-Path $script:LAST_DESCTINATION_PATH)) {
        $dialog.SelectedPath = $script:LAST_DESCTINATION_PATH
    }

    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:LAST_DESCTINATION_PATH = $dialog.SelectedPath
        return $script:LAST_DESCTINATION_PATH
    }
    else {
        return $null
    }
}

function Open-GridResultFiles {
    param ([System.Windows.Forms.DataGridView]$grid)

    $files = @(Get-GridResultSelectedUniqueFiles -grid $grid)
    if ($files.Count -eq 0) { return }

    $i = 0
    foreach ($file in $files) {
        Open-FileView $file
        $i++
        if ($i -ge 20) { break }
    }
}

function Open-GridResultFileFolders {
    param ([System.Windows.Forms.DataGridView]$grid)

    $files = @(Get-GridResultSelectedUniqueFiles -grid $grid)
    if ($files.Count -eq 0) { return }

    $i = 0
    foreach ($file in $files) {
        Open-FileFolder $file
        $i++
        if ($i -ge 20) { break }
    }
}

function Get-GridResultSelectedUniqueFiles {
    param ([System.Windows.Forms.DataGridView]$grid)

    $rows = $grid.SelectedRows
    if ($null -eq $rows -or $rows.Count -eq 0) { return ,@() }

    $files = @()
    foreach ($row in $rows) {
        $filePath = $row.Cells["FilePath"].Value
        $files += $filePath
    }
    
    return @(Get-UniqueStringValuesArray -Arr $files)
}

function Add-ToSearchResult {
    param(
        [string]$resultFilePath,
        [System.Collections.Specialized.OrderedDictionary]$values
    )

    $grid = $script:GUI_CONTROLS.gridResults
    $script:APP_CONTEXT.totalFound++

    $values["#"] = $script:APP_CONTEXT.totalFound

    Add-GridRow -grid $grid -values $values

    $script:APP_CONTEXT.session.unsaved = $true

    if (-not $resultFilePath) { return }
    Add-ValueToResultFile -savePath $resultFilePath -values $values # - Headers is not important, just values order
}
