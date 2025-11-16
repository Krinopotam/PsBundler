. "$PSScriptRoot/formMethods.ps1"
. "$PSScriptRoot/ui/advancedGrid/methods.ps1"

function Save-Session {
    try {
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "XML files (*.xml)|*.xml"
        $dialog.FileName = "search-session.xml"
        if ($dialog.ShowDialog() -ne 'OK') { return }

        $gridResults = $script:GUI_CONTROLS.gridResults
        $gridLocations = $script:GUI_CONTROLS.gridLocations
        $gridSearchPatterns = $script:GUI_CONTROLS.gridSearchPatterns
        $state = @{}

        $pbStep = 0
        $pb = Start-ProgressBar -Total 3 -Label "Saving..." -canStop $true

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $dtResultsXml = New-Object System.IO.StringWriter
        $dtResults = $gridResults.DataSource.DataSource
        if (-not $dtResults.TableName) { $dtResults.TableName = "GridResults" }
        $dtResults.WriteXml($dtResultsXml, [System.Data.XmlWriteMode]::WriteSchema)
        $pbStep++
        $pb.Update($pbStep)

        $dtLocationsXml = New-Object System.IO.StringWriter
        $dtLocations = $gridLocations.DataSource.DataSource
        if (-not $dtLocations.TableName) { $dtLocations.TableName = "GridLocations" }
        $dtLocations.WriteXml($dtLocationsXml, [System.Data.XmlWriteMode]::WriteSchema)
        $pbStep++
        $pb.Update($pbStep)

        $dtSearchPatternsXml = New-Object System.IO.StringWriter
        $dtSearchPatterns = $gridSearchPatterns.DataSource.DataSource
        if (-not $dtSearchPatterns.TableName) { $dtSearchPatterns.TableName = "GridSearchPatterns" }
        $dtSearchPatterns.WriteXml($dtSearchPatternsXml, [System.Data.XmlWriteMode]::WriteSchema)
        $pbStep++
        $pb.Update($pbStep)


        $resumeLocationValue = $null
        $resumeLocationType = $null
        $resumeFilePath = $null
        $totalFound = 0
        if ($script:APP_CONTEXT.session) {
            $resumeLocationValue = $script:APP_CONTEXT.session.locationValue
            $resumeLocationType = $script:APP_CONTEXT.session.locationType
            $resumeFilePath = $script:APP_CONTEXT.session.filePath
            $totalFound = $script:APP_CONTEXT.totalFound
        }

        $state["GridResults"] = $dtResultsXml.ToString()
        $state["GridLocations"] = $dtLocationsXml.ToString()        
        $state["GridSearchPatterns"] = $dtSearchPatternsXml.ToString()
        $state["AllowedMasks"] = $script:GUI_CONTROLS.txtAllowedMasks.Text
        $state["ExcludedMasks"] = $script:GUI_CONTROLS.txtExcludedMasks.Text
        $state["MaxFileSize"] = $script:GUI_CONTROLS.cbMaxFileSize.Text
        $state["Encodings"] = Get-TabConfigEncodings
        $state["AutoSaveResults"] = $script:GUI_CONTROLS.chbAutoSaveResults.Checked
        $state["ResultFilePath"] = $script:GUI_CONTROLS.txtAutoSaveResults.Text.Trim()
        $state["FileDateStart"] = $script:GUI_CONTROLS.dpFileDateStart.Text
        $state["FileDateEnd"] = $script:GUI_CONTROLS.dpFileDateEnd.Text
        $state["ResumeLocationValue"] = $resumeLocationValue
        $state["ResumeLocationType"] = $resumeLocationType
        $state["ResumeFilePath"] = $resumeFilePath
        $state["VisitedPaths"] = $script:APP_CONTEXT.session.visitedPaths
        $state["TotalFound"] = $totalFound

        $state | Export-Clixml $dialog.FileName

        $pb.Close()
        $sw.Stop()

        $script:APP_CONTEXT.session.unsaved = $false
        $time = Format-SecondsToReadableTime -seconds $sw.Elapsed.TotalSeconds

        Show-Info "Session saved to file: $($dialog.FileName) in $time"
    }
    catch {
        $pb.Close()
        Write-Error "Failed to save session: $($_.Exception)"
        Show-Error "Failed to save session: $($_.Exception.Message)"
    }
}

function Restore-Session {
    if ($PSVersionTable.PSVersion.Major -lt 5) { 
        # PowerShell 2.0 can't readXml with schema (component is not initialized error)
        Show-Error "This function is not supported in PowerShell 2.0"
        return 
    }

    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "XML files (*.xml)|*.xml"
        if ($dialog.ShowDialog() -ne 'OK') { return }


        if (-not (Test-Path $dialog.FileName)) {
            Show-Error "File not found: $($dialog.FileName)"
            return $null
        }

        $gridResults = $script:GUI_CONTROLS.gridResults
        $gridLocations = $script:GUI_CONTROLS.gridLocations
        $gridSearchPatterns = $script:GUI_CONTROLS.gridSearchPatterns

        $pbStep = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $pb = Start-ProgressBar -Total 3 -Label "Loading..." -canStop $true 

        $state = Import-Clixml $dialog.FileName

        $reader = New-Object System.IO.StringReader($state["GridSearchPatterns"])
        $dtPatterns = New-Object System.Data.DataTable
        [void]$dtPatterns.ReadXml($reader)
        $gridSearchPatterns.DataSource.DataSource = $dtPatterns
        $pbStep++
        $pb.Update($pbStep)

        $reader = New-Object System.IO.StringReader($state["GridLocations"])
        $dtLocations = New-Object System.Data.DataTable
        [void]$dtLocations.ReadXml($reader)
        $gridLocations.DataSource.DataSource = $dtLocations
        $pbStep++
        $pb.Update($pbStep)

        $reader = New-Object System.IO.StringReader($state["GridResults"])
        $dtResults = New-Object System.Data.DataTable
        [void]$dtResults.ReadXml($reader)
        $gridResults.DataSource.DataSource = $dtResults
        $pbStep++
        $pb.Update($pbStep)

        $script:GUI_CONTROLS.txtAllowedMasks.Text = $state["AllowedMasks"]
        $script:GUI_CONTROLS.txtExcludedMasks.Text = $state["ExcludedMasks"]
        $script:GUI_CONTROLS.cbMaxFileSize.Text = $state["MaxFileSize"]
        Set-TabConfigEncodings -encodings $state["Encodings"]
        $script:GUI_CONTROLS.dpFileDateStart.Text = $state["FileDateStart"]
        $script:GUI_CONTROLS.dpFileDateEnd.Text = $state["FileDateEnd"]
        $script:GUI_CONTROLS.chbAutoSaveResults.Checked = $state["AutoSaveResults"]
        $script:GUI_CONTROLS.txtAutoSaveResults.Text = $state["ResultFilePath"]
        $script:APP_CONTEXT.session.locationValue = $state["ResumeLocationValue"]
        $script:APP_CONTEXT.session.locationType = $state["ResumeLocationType"]
        $script:APP_CONTEXT.session.filePath = $state["ResumeFilePath"]
        $script:APP_CONTEXT.session.visitedPaths = $state["VisitedPaths"]
        $script:APP_CONTEXT.totalFound = [int]$state["TotalFound"]

        if ($script:APP_CONTEXT.session.locationValue -and $script:APP_CONTEXT.session.locationType -and $script:APP_CONTEXT.session.filePath) {
            $script:GUI_CONTROLS.txtStatusBar.Text = "Search stopped at $($script:APP_CONTEXT.session.filePath)"
        }
        else { $script:GUI_CONTROLS.txtStatusBar.Text = "Session resumed" }

        Set-RunningState -val $false | Out-Null

        $script:APP_CONTEXT.session.unsaved = $false

        $pb.Close()
        $time = Format-SecondsToReadableTime -seconds $sw.Elapsed.TotalSeconds
        Show-Info "Session loaded in $time"
    }
    catch {
        $pb.Close()
        Write-Error "Error loading session: $($_.Exception)"
        Show-Error "Error loading session: $($_.Exception.Message)"
    }
}
