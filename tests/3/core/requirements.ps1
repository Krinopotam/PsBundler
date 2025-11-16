. "$PSScriptRoot/../core/handlers.ps1"
. "$PSScriptRoot/../gui/formMethods.ps1"
. "$PSScriptRoot/../gui/ui/alerts/alerts.ps1"
. "$PSScriptRoot/../parsers/outlook.ps1"
#. "$PSScriptRoot/../parsers/word.ps1"
#. "$PSScriptRoot/../parsers/excel.ps1"

# ---------- Check application requirements --------------------
function Test-Requirements {
    param(
        [boolean]$gui,
        [scriptblock]$onError,
        [scriptblock]$onWarning
    )

    if ($gui) {
        $onError = Get-OnErrorHandler
        $onWarning = Get-OnInfoHandler
    }
    else {
        $onError = Get-OnErrorCoreHandler
        $onWarning = Get-OnInfoCoreHandler
    }

    $appContext = $script:APP_CONTEXT

    $info = ""

    #region Check PS version
    $psVer = $PSVersionTable.PSVersion
    
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        $info = $info + "Recommended to powershell version 5.1. Current version is: $psVer. Some features may be unsupported.`r`n"
    }
    #endregion
    
    #region Check ZIP
    if ($appContext.features.zip -ne $false) {

        try {
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $appContext.features.zip = $true
        }
        catch {
            $info = "The module System.IO.Compression could not be loaded. The searching in .zip files is not available.`r`n"
            $appContext.features.zip = $false
        }
    }
    #endregion


    #region Check Outlook
    if ($appContext.features.outlook -ne $false) {
        $appContext.features.outlook = Initialize-OutlookInstance
    
        if (-not $appContext.features.outlook) { $info = $info + "MS Outlook could not be loaded. Searching in .msg files is not available.`r`n" }
    }
    #endregion

    #region Check Word
    if ($appContext.features.word -ne $false) {
        $appContext.features.word = Initialize-WordInstance
    
    
        if (-not $appContext.features.word) { 
            if (-not $appContext.features.zip) {
                $info = $info + "MS Word could not be loaded. Searching in MS Word files (.docx, .docm, .doc, .rtf) is not available.`r`n"
            }
            else {
                $info = $info + "MS Word could not be loaded. Searching in old binary MS Word files (.doc and .rtf) is not available.`r`n" 
            }
        }
    }
    #endregion

    #region Check Excel
    if ($appContext.features.excel -ne $false) {
        $appContext.features.excel = Initialize-ExcelInstance
    
        if (-not $appContext.features.excel) { 
            if (-not $appContext.features.zip) {
                $info = $info + "MS Excel could not be loaded. Searching in MS Excel files (.xlsx, .xlsm, .xls) is not available.`r`n"
            }
            else {
                $info = $info + "MS Excel could not be loaded. Searching in old binary MS Excel files (.xls) is not available.`r`n" 
            }
        }
    }
    #endregion

    if ($info -ne "") { &$onWarning $info } 

    if (-not $gui) { return }

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $err = "GUI requires STA-thread. Please restart PowerShell with -STA key"
        &$onError $err 
        exit
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        
    }
    catch {
        $err = "The module System.Windows.Forms cannot be loaded"
        &$onError $err
        exit
    }
}