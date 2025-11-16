. "$PSScriptRoot/../core/searchRegex.ps1"

# ---------- Check if file is MS outlook msg file ---------------
function Test-IsMsg {
    param ([System.IO.FileInfo]$file)
    return ($file.Extension.ToLower() -eq ".msg") 
}

function Initialize-OutlookInstance {
    try {
        #$outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
        $outlook = [System.Activator]::CreateInstance(
            [System.Type]::GetTypeFromProgID("Outlook.Application", $null)
        )
        
        $namespace = $outlook.GetNamespace("MAPI")
        
        return @{
            outlook   = $outlook
            namespace = $namespace
        }
    }
    catch {
        return $false
    }
}

function Close-OutlookInstance {
    param (
        [System.Collections.IDictionary]$appContext
    )

    if (-not $appContext.features.outlook) { return }

    $outlook = $appContext.features.outlook.outlook
    $namespace = $appContext.features.outlook.namespace


    try {
        if ($namespace) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($namespace) | Out-Null
            $namespace = $null
        }

        if ($outlook) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
            $outlook = $null
        }

        $appContext.features.outlook = $null
    }
    catch { }
}

function Get-OutlookMsgContent {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file
    )

    $namespace = $searchParams.appContext.features.outlook.namespace
    $msg = $null

    try {
        $msg = $namespace.OpenSharedItem($file.FullName)

        $result = "$($msg.Subject)`r`n$($msg.Body)"

        return $result
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $msg) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($msg) | Out-Null }
    }
}

# ---------- Search in MS Word docx file for patterns ----------
function Search-InMsg {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    if (-not $searchParams.appContext.features.outlook) { return $false }

    $content = Get-OutlookMsgContent -searchParams $searchParams -file $file
    if ($null -eq $content) { return $false }

    $null = Test-ContentForPatterns -searchParams $searchParams `
        -content $content `
        -filePath $file.FullName `
        -fileName $file.Name `
        -fileSize $file.Length `
        -fileDate $file.LastWriteTime `
        -deduplicatedMatches $deduplicatedMatches
    return $true
}