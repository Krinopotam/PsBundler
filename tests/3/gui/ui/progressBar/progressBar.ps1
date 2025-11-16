function Start-ProgressBar {
    param(
        [int]$Total,
        [string]$Label = "",
        [boolean]$canStop = $false,
        [int]$ThrottlePercent = 5  # minimum UI update interval in percents
    )

    $mainForm = $script:GUI_CONTROLS.form

    # Create form
    $formHeight = if ($canStop) { 120 } else { 90 }
    $form = New-Object System.Windows.Forms.Form
    $form.Text = ""
    $form.Size = New-Object System.Drawing.Size(300, $formHeight)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.ControlBox = $false
    #$form.TopMost = $true
    $form.ShowInTaskbar = $false

    $form.Top = $mainForm.Top + [int](($mainForm.Height - $form.Height) / 2)
    $form.Left = $mainForm.Left + [int](($mainForm.Width - $form.Width) / 2)

    # Progress label
    $progressLabel = New-Object System.Windows.Forms.Label
    $progressLabel.AutoSize = $true
    $progressLabel.Location = New-Object System.Drawing.Point(20, 15)
    $progressLabel.Text = $Label

    # ProgressBar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $progressBar.Step = 1
    $progressBar.Style = "Continuous"
    $progressBar.Size = New-Object System.Drawing.Size(260, 20)
    $progressBar.Location = New-Object System.Drawing.Point(20, 35)

    # Percent label
    $percentLabel = New-Object System.Windows.Forms.Label
    $percentLabel.AutoSize = $true
    $percentLabel.Location = New-Object System.Drawing.Point(130, 60)
    $percentLabel.Text = "0 %"

    # Cancel button
    if ($canStop) {
        $btnStop = New-Object System.Windows.Forms.Button
        $btnStop.Text = "Cancel"
        $btnStop.Width = 80
        $btnStop.Height = 25
        $btnStop.Location = New-Object System.Drawing.Point(($progressBar.Right - $btnStop.Width), ($form.Height - $btnStop.Height - 20))
        $btnStop.Add_Click({ 
                param($s, $e)

                $pb = $s.Parent.Tag
                $s.Text = "Cancelling..."
                $s.Enabled = $false
                $pb.IsCanceled = $true
            })
        $form.Controls.Add($btnStop)
    }

    $form.Controls.Add($progressLabel)
    $form.Controls.Add($progressBar)
    $form.Controls.Add($percentLabel)


    $mainForm.Enabled = $false

    # Create object
    $pb = New-Object PSObject
    $pb | Add-Member -MemberType NoteProperty -Name "Total" -Value $Total
    $pb | Add-Member -MemberType NoteProperty -Name "Form" -Value $form
    $pb | Add-Member -MemberType NoteProperty -Name "ProgressBar" -Value $progressBar
    $pb | Add-Member -MemberType NoteProperty -Name "PercentLabel" -Value $percentLabel
    $pb | Add-Member -MemberType NoteProperty -Name "ThrottlePercent" -Value $ThrottlePercent
    $pb | Add-Member -MemberType NoteProperty -Name "CurrentValue" -Value 0
    $pb | Add-Member -MemberType NoteProperty -Name "IsCanceled" -Value $false
    $pb | Add-Member -MemberType NoteProperty -Name "LastPercent" -Value 0

    # Update method
    $updateScript = {
        param($Value)
        $this.CurrentValue = $Value

        if ($this.Total -eq 0) { return }   

        $percent = [math]::Round(($this.CurrentValue / $this.Total) * 100)
        if ($percent -gt 100) { $percent = 100 }

        if (-not $this.LastPercent) { $this.LastPercent = 0 }

        # Refresh only if moved at least $ThrottlePercent or reached the end
        if (($percent - $this.LastPercent) -ge $this.ThrottlePercent -or $percent -eq 100) {
            $this.ProgressBar.Value = $percent
            $this.PercentLabel.Text = "$percent %"
            [System.Windows.Forms.Application]::DoEvents()

            $this.LastPercent = $percent
        }
    }
    $pb | Add-Member -MemberType ScriptMethod -Name "Update" -Value $updateScript

    # Close method
    $closeScript = {
        $mainForm = $script:GUI_CONTROLS.form
        $mainForm.Enabled = $true
        $this.Form.Close()
        $this.Form.Dispose()
    }
    $pb | Add-Member -MemberType ScriptMethod -Name "Close" -Value $closeScript

    $form.Tag = $pb

    $form.Show($mainForm)
    $form.Refresh()
    
    return $pb
}