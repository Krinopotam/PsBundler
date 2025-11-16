function Start-Debounce {
    param(
        [object]$StateObj,      # Object to debounce (control, button, etc.)
        [scriptblock]$Action,  # ScriptBlock to execute
        [int]$DelayMs = 300
    )

    # FALLBACK: old versions of PS is ugly, use debounce in newer versions only
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        & $Action $StateObj
        return
    }

    # Stop old timer
    if ($StateObj.PSObject.Properties["_DebounceTimer"] -and $StateObj._DebounceTimer) {
        $StateObj._DebounceTimer.Stop()
        $StateObj._DebounceTimer.Dispose()
        $StateObj._DebounceTimer = $null
    }

    # Create new timer
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $DelayMs

    # Keep StateObj instance in timer
    $timer | Add-Member -MemberType NoteProperty -Name "_StateObj" -Value $StateObj

    # Run action when timer ticks and cleanup timer
    $timer.Add_Tick({
            param($t, $e)

            $obj = $t._StateObj
            $action = $obj._Action
            $obj._DebounceTimer.Stop()
            $obj._DebounceTimer.Dispose()
            $obj._DebounceTimer = $null

            & $action $obj
        })

    # Keep timer in target
    $StateObj | Add-Member -MemberType NoteProperty -Name "_DebounceTimer" -Value $timer -Force
    $StateObj | Add-Member -MemberType NoteProperty -Name "_Action" -Value $Action -Force

    $timer.Start()
}
