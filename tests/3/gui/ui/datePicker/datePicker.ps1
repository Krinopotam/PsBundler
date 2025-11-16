
. "$PSScriptRoot/../../../helpers/strings.ps1"

function New-DatePicker {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Width = 150
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    $dateBox = New-Object System.Windows.Forms.MaskedTextBox
    $btnCalendar = New-Object System.Windows.Forms.Button
    $btnClear = New-Object System.Windows.Forms.Button
    $calendar = New-Object System.Windows.Forms.MonthCalendar
    $calendarHost = New-Object System.Windows.Forms.ToolStripControlHost($calendar)
    $dropDown = New-Object System.Windows.Forms.ToolStripDropDown
    [void]$dropDown.Items.Add($calendarHost)

    # -------- Panel properties --------------------
    $panel | Add-Member -MemberType NoteProperty -Name __props -Value @{ 
        dateBox     = $dateBox
        btnCalendar = $btnCalendar
        btnClear    = $btnClear
        calendar    = $calendar
        dropDown    = $dropDown
        value       = $null            
    }

    $panel | Add-Member -MemberType ScriptProperty -Name Value `
        -Value { return $this.__props.value } `
        -SecondValue {
        param($val)
        $dateBox = $this.__props.dateBox
        $this.__props.value = Convert-ToDateTime $val
        if ($null -eq $this.__props.value) { $dateBox.text = '' }
        else { $dateBox.Text = $this.__props.value.ToString("dd.MM.yyyy") }
    }

    $panel | Add-Member -MemberType ScriptProperty -Name Text -Force `
        -Value { 
        if (-not $this.__props.value) { return '' }
        return $this.__props.value.ToString("dd.MM.yyyy") 
    } `
        -SecondValue {
        param($val)
        $this.Value = $val
    }

    $panel | Add-Member -MemberType ScriptMethod -Name ShowCalendar -Value {
        param([boolean]$show = $true)

        if (-not $show) {
            $this.__props.dropDown.Close()
            return
        } 
        
        $btnCalendar = $this.__props.btnCalendar
        $dropDown = $this.__props.dropDown
        $dateBox = $this.__props.dateBox
        $calendar = $this.__props.calendar

        $text = $dateBox.Text.Trim()
        $dt = Convert-ToDateTime $text

        if ($null -eq $dt) { $dt = [datetime]::Today } 

        $calendar.SelectionStart = $dt
        $calendar.SelectionEnd = $dt

        $screenPoint = $btnCalendar.PointToScreen((New-Object System.Drawing.Point 0, $btnCalendar.Height))
        $dropDown.Show($screenPoint)
    } 

    $panel | Add-Member -MemberType ScriptProperty -Name BorderStyle -Force `
        -Value { return $this.__props.dateBox.BorderStyle } `
        -SecondValue {
        param($val)
        $this.__props.dateBox.BorderStyle = $val
    }

    $panel | Add-Member -MemberType ScriptProperty -Name BackColor -Force `
        -Value { return $this.__props.dateBox.BackColor } `
        -SecondValue {
        param($val)
        $this.__props.dateBox.BackColor = $val
    }

    $panel | Add-Member -MemberType ScriptProperty -Name ForeColor -Force `
        -Value { return $this.__props.dateBox.ForeColor } `
        -SecondValue {
        param($val)
        $this.__props.dateBox.ForeColor = $val
    }

    #endregion

    #region ---------- DateBox properties --------------------
    $dateBox.Mask = "00.00.0000"
    $dateBox.TextMaskFormat = [System.Windows.Forms.MaskFormat]::IncludeLiterals
    $dateBox.PromptChar = '_'
    $dateBox.Width = $panel.Width - 23 * 2 - 4
    $dateBox.Left = 0
    $dateBox.Top = 0
    $dateBox.Anchor = "Top, Left, Right"
    $dateBox.Tag = @{ panel = $panel }
    $dateBox.Add_Validating({
            param($s, [System.ComponentModel.CancelEventArgs]$e)

            $panel = $s.Tag.panel
            $text = $s.Text.Trim()

            $s.TextMaskFormat = [System.Windows.Forms.MaskFormat]::ExcludePromptAndLiterals
            $hasValue = $s.Text.Trim().Length -gt 0
            $s.TextMaskFormat = [System.Windows.Forms.MaskFormat]::IncludeLiterals
            if (-not $hasValue) {
                $s.Text = $null
                $panel.__props.value = $null
                return
            }   

            $dt = Convert-ToDateTime $text
            if (-not $dt) { $dt = $panel.__props.value }
            $panel.__props.value = $dt

            if ($null -eq $dt) { $s.Text = $null }
            else { $s.Text = $dt.ToString('dd.MM.yyyy') }
        })
    #endregion

    #region ---------- Calendar Button properties --------------------
    $btnCalendar.Text = "..."
    $btnCalendar.Width = 23
    $btnCalendar.Height = $dateBox.Height
    $btnCalendar.Left = $dateBox.Right + 2
    $btnCalendar.Top = $dateBox.Top
    $btnCalendar.Anchor = "Top, Right"
    $btnCalendar.Tag = @{ panel = $panel } # WORKAROUND: In PS 5 "$btnCalendar.Tag = $panel" will not help. Callback will not see $panel.ShowCalendar
    $btnCalendar.Add_Click({
            param($s, $e)
            $panel = $s.Tag.panel
            $panel.ShowCalendar()
        })
    #endregion

    #region ---------- Clear Button properties --------------------
    $btnClear.Text = "x"
    $btnClear.Width = 23
    $btnClear.Height = $dateBox.Height
    $btnClear.Left = $btnCalendar.Right + 2
    $btnClear.Top = $dateBox.Top
    $btnClear.Anchor = "Top, Right"
    $btnClear.Tag = @{ panel = $panel }
    $btnClear.Add_Click({
            param($s, $e)
            $panel = $s.Tag.panel
            $dateBox = $panel.__props.dateBox
            $panel.__props.value = $null
            $dateBox.Text = $null
        })
    #endregion

    #region ---------- Calendar properties --------------------
    $calendar.MaxSelectionCount = 1
    $calendar.Tag = @{ panel = $panel }
    $calendar.Add_DateSelected({
            param($s, $e)
            $panel = $s.Tag.panel
            $dropDown = $panel.__props.dropDown
            $dateBox = $panel.__props.dateBox
            $sel = $e.Start
            $panel.__props.value = $sel
            $dateBox.Text = $sel.ToString('dd.MM.yyyy')

            try {
                $dropDown.Close()
            }
            catch {}
        })

    #endregion

    $panel.Height = $dateBox.Height
    $panel.Controls.Add($dateBox)
    $panel.Controls.Add($btnCalendar)
    $panel.Controls.Add($btnClear)

    return $panel
}