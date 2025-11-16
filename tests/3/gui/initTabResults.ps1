. "$PSScriptRoot/formConstants.ps1"
. "$PSScriptRoot/initGridResults.ps1"

function Initialize-TabResults {
    param (
        [System.Windows.Forms.Form]$form,
        [System.Windows.Forms.TabControl]$tabControl
    )

    $tabPageResult = New-Object System.Windows.Forms.TabPage
    $script:GUI_CONTROLS.tabPageResult = $tabPageResult
    $tabPageResult.Name = "tabPageResult"
    $tabPageResult.Text = 'Results'
    $tabControl.TabPages.Add($tabPageResult)
    [void]$tabPageResult.Handle # force creation to make tabPageResult has real size

    #region ---------- Result Grid output --------------------------------
    Initialize-GridResults -form $form -container $tabPageResult | Out-Null
    #endregion
    
}