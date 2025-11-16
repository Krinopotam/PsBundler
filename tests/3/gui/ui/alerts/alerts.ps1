# ---------- Helper to show error alert ------------------------
function Show-Error {
    param ([string] $msg)
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($script:GUI_CONTROLS.form, $msg, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# ---------- Helper to show infi alert -------------------------
function Show-Info {
    param ([string] $msg)
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($script:GUI_CONTROLS.form, $msg, "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}