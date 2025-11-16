#region ---------- Find Control on form -------------------------------
function Find-FormControl {
    param (
        [System.Windows.Forms.Control]$container,
        [string]$name
    )

    foreach ($control in $container.Controls) {
        if ($control.Name -eq $name) { return $control }
        if ($control.HasChildren) {
            $found = Find-FormControl -container $control -name $name
            if ($found) { return $found }
        }

        if (-not ($control -is [System.Windows.Forms.ToolStrip])) { continue }

        # For controls like ToolStrip we need to check items
        foreach ($item in $control.Items) {
            if ($item.Name -eq $name) { return $item }
        }
    }

    return $null
}

function Set-ControlEnabledRecursive {
    param (
        [System.Windows.Forms.Control]$container,
        [boolean]$state,
        [hashtable]$ignore
    )

    foreach ($control in $container.Controls) {
        if ($control.HasChildren) {
            if ($ignore -and $ignore[$control.Name]) { continue }
            
            $control.Enabled = $state
            Set-ControlEnabledRecursive -container $control -state $state -ignore $ignore
        }
    }
}