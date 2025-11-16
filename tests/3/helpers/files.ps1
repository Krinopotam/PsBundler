. "$PSScriptRoot/objects.ps1"
. "$PSScriptRoot/../gui/ui/alerts/alerts.ps1"

# ---------- Check if file is matching file masks --------------
function Test-FileNameMaskMatch {
    param (
        [string]$fileName,
        [string]$extension,
        [string[]]$masks
    )

    $fileName = $fileName.ToLower()

    if ($extension -eq "") { $fileName = $fileName + "." }

    foreach ($mask in $masks) {
        if ($fileName -like $mask) { return $true }
    }

    return $false
}


# ---------- Open explorer to file directory -------------------
function Open-FileFolder {
    param (
        [string]$filePath
    )

    try {
        if ([string]::IsNullOrEmpty($filePath)) { return }

        if (-not (Test-Path -LiteralPath $filePath)) {
            Show-Error "File no exists: $filePath"
            return
        }

        Start-Process explorer.exe -ArgumentList "/select,`"$filePath`""
    }
    catch {
        Show-Error "Failed to open file folder: $filePath"
    }
}

# ---------- View file in notepad ------------------------------
function Open-FileView {
    param (
        [string]$filePath
    )

    try {
        if ([string]::IsNullOrEmpty($filePath)) { return }

        if (-not (Test-Path -LiteralPath $filePath)) {
            Show-Error "File no exists: $filePath"
            return
        }

        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()

    
        $openWithDefault = @(
            '.doc', '.docx', ".docm", '.xls', '.xlsx', '.xlsm', '.ppt', '.pptx', '.msg', '.rtf',          # Office
            '.mdb', '.accdb',                                                                             # Access
            '.pdf',                                                                                       # PDF
            '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff', '.tif', '.tga', '.svg', '.webp', '.ico',    # Images
            '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'                                                  # Archives
        )

        if ($openWithDefault -contains $ext) {
            Start-Process $filePath
        }
        else {
            Start-Process -FilePath "notepad.exe" -ArgumentList "`"$filePath`""
        }
    }
    catch {
        Show-Error "Failed to open file: $filePath"
    }
}

function Copy-FilesToClipboard {
    param (
        [System.Collections.Specialized.StringCollection]$fileList
    )

    [System.Windows.Forms.Clipboard]::SetFileDropList($fileList)
}

# Copy file with full path
function Copy-FileWithFullPath {
    param(
        [string]$SourceFile,
        [string]$DestRoot
    )

    try {
        if (-not (Test-Path $SourceFile)) { 
            return "File not found." 
        }

        # Replace colons
        $relativePath = $SourceFile -replace ":", ""

        # Make relative network path 
        if ($relativePath -like "\\*") {
            $relativePath = $relativePath.TrimStart("\")
        }

        $destFile = Join-Path $DestRoot $relativePath

        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item -Path $SourceFile -Destination $destFile -Force | Out-Null
        return $null
    }
    catch {
        return $_.Exception.Message
    }
}

function Add-ContentToFileSafely {
    param(
        [string]$Path,
        [string]$Value,
        [string]$Encoding = "utf8",
        [int]$MaxRetries = 5,
        [int]$DelayMs = 100
    )

    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            Add-Content -Path $Path -Value $Value -Encoding $Encoding
            return 
        }
        catch {
            if ($i -eq $MaxRetries - 1) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

# ---------- Add value to result file --------------------------
function Add-ValueToResultFile {
    param (
        [string]$savePath,
        $values # No type specified because it want to be ordered hashtable
    )

    if ([string]::IsNullOrEmpty($savePath)) { return }

    try {
        $object = Convert-HashtableToPSObject $values
        $csvLines = @($object | ConvertTo-Csv -NoTypeInformation -Delimiter ";")

        if ($csvLines.Length -gt 1) {
            # Add-Content -Path $savePath -Value $csvLines[1] -Encoding utf8
            Add-ContentToFileSafely -Path $savePath -Value $csvLines[1] -Encoding utf8 | Out-Null
        }
    }
    catch {
        Write-DebugErrorLog $_
    }
}

# Check if directory is part of file path
function Test-DirInPath($filePath, $dirPath) {
    if (-not $dirPath.EndsWith('\')) { $dirPath += '\' }
    $isPart = $filePath.StartsWith($dirPath, [StringComparison]::OrdinalIgnoreCase)
    return $isPart
}

function Test-DirIsFileParent($filePath, $dirPath) {
    if ($dirPath.EndsWith('\') -and $dirPath.Length -gt 3) { $dirPath = $dirPath.TrimEnd('\') } # if dir like "c:\"" don't remove last "\""
    $fileParent = Split-Path $filePath -Parent
    return $fileParent.Equals($dirPath, [System.StringComparison]::OrdinalIgnoreCase)
}


function Write-Log {
    param (
        [string]$msg,
        [string]$logFile = "log.txt",
        [string]$type = "Info"
    )

    $curDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "$curDateTime" + ": " + "$msg"
    
    if ($script:LOG_TO_SCREEN) {
        $color = "White"
        if ($type -eq "Error") { $color = "Red" }
        elseif ($type -eq "Warning") { $color = "Yellow" }
        elseif ($type -eq "Info") { $color = "Cyan" }
        
        Write-Host $output -ForegroundColor $Color
    }
    else {
        Add-Content -Path $logFile -Value $output
    }
}

function Write-DebugLog {
    param (
        [string]$msg,
        [string]$logFile = "log.txt"
    )
    $isDebug = Get-IsDebug
    if (-not $isDebug) { return }

    Write-Log -msg $msg -logFile $logFile -type "Info"
}

function Write-DebugErrorLog {
    param (
        [System.Management.Automation.ErrorRecord]$err,
        [string]$prefix = "Error:",
        [string]$logFile = "log.txt"
    )

    $isDebug = Get-IsDebug
    if (-not $isDebug) { return }

    $msg = Get-ErrorText -err $err -prefix $prefix
    Write-Log -msg $msg -logFile $logFile -type "Error"
    
}

function Get-IsDebug {
    return ($DebugPreference -eq 'Continue' -or $DebugPreference -eq 'Inquire' -or $DebugPreference -eq 'Stop')
}

