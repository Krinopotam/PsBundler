# --------- Returns prepared search parameters hash ---------
function Get-PreparedParams {
    param (
        [hashtable]$params
    )   

    $allowedMasks = "*.*"
    if ($params.allowedMasks.trim()) { $allowedMasks = $params.allowedMasks.trim() }

    $patterns = Split-PatternsByType -patterns $params.searchPatterns
    $locations = Convert-LocationsByType -locations $params.locations

    $resultFilePath = $params.resultFilePath.Trim()
    if (-not [string]::IsNullOrEmpty($resultFilePath)) { $resultFilePath = [System.IO.Path]::GetFullPath($resultFilePath) }

    $searchParams = @{}

    # Set unchanged params
    foreach ($key in $params.Keys) {
        $searchParams[$key] = $params[$key]
    }

    # Set specific params
    $searchParams.contentPatterns = $patterns.Content 
    $searchParams.filenamePatterns = $patterns.Filename
    $searchParams.locations = $locations
    $searchParams.allowedMasks = Split-StringToArray -str $allowedMasks
    $searchParams.excludedMasks = Split-StringToArray -str $params.excludedMasks
    $searchParams.maxFileSize = Convert-ToBytes -size $params.maxFileSize
    $searchParams.encodings = Split-StringToEncodings -encodings $params.encodings
    $searchParams.fileDateStart = Convert-ToDateTime $params.fileDateStart
    $searchParams.fileDateEnd = Convert-ToDateTime $params.fileDateEnd
    $searchParams.resultFilePath = $resultFilePath

    return $searchParams
}

# --------- Splits patterns by type (Filename/Content) ---------
function Split-PatternsByType {
    param (
        [hashtable[]]$patterns
    )

    $contentItems = @()
    $filenameItems = @()

    foreach ($item in $patterns) {
        if ($item.ContainsKey("Selected") -and -not $item["Selected"]) { continue }

        if (-not $item.ContainsKey("Type") -or -not $item.ContainsKey("Pattern")) { 
            Write-Verbose "Invalid pattern: $item"
            continue 
        }

        $pattern = @{
            Type             = $item.Type
            Pattern          = $item.Pattern
            Desc             = $item.Desc
            IncludedMasks    = if ($item.ContainsKey("IncludedMasks")) { Split-StringToArray -str $item.IncludedMasks } else { $null }
            ExcludedMasks    = if ($item.ContainsKey("ExcludedMasks")) { Split-StringToArray -str $item.ExcludedMasks } else { $null }
            MaxContentLength = if ($item.ContainsKey("MaxContentLength") -and -not [string]::IsNullOrEmpty($item.MaxContentLength)) { Convert-ToInt -str $item.MaxContentLength } else { $null }
            MinFileSize      = if ($item.ContainsKey("MinFileSize") -and -not [string]::IsNullOrEmpty($item.MinFileSize)) { Convert-ToBytes -size $item.MinFileSize } else { $null } 
            MaxFileSize      = if ($item.ContainsKey("MaxFileSize") -and -not [string]::IsNullOrEmpty($item.MaxFileSize)) { Convert-ToBytes -size $item.MaxFileSize } else { $null } 
        }

        if ($item.type -ieq 'Content') { $contentItems += $pattern } 
        elseif ($item.type -ieq 'Filename') { $filenameItems += $pattern }
    }

    return @{
        Content  = $contentItems
        Filename = $filenameItems
    }
}

# --------- Splits locations by type (Folder/Host) ---------
function Convert-LocationsByType {
    param (
        [hashtable[]]$locations
    )

    $items = @()

    foreach ($item in $locations) {
        if (-not $item.ContainsKey("Selected") -or -not $item["Selected"]) { continue }

        if (-not $item.ContainsKey("type") -or -not $item.ContainsKey("value")) { 
            Write-Verbose "Invalid location: $item"
            continue 
        }

        $itemType = $item.type.ToLower()
        if ($itemType -ieq 'folder' -or $itemType -ieq 'host') { $items += $item } 
        elseif ($itemType -ieq 'ip range') {
            $range = Split-IpRangeToParts $item.value
            if ($null -eq $range) { continue }
            $ipRanges = Get-IpRangesList -startIp $range.startIp -endIp $range.endIp
            $desc = $item['desc']
            
            foreach ($ip in $ipRanges) {
                $hostVal = $ip
                $type = "Host"

                if ($range['folder']) { 
                    $hostVal = "\\$ip$($range.folder)" 
                    $type = "Folder"
                }

                $ipItem = @{ type = $type; value = $hostVal; desc = $desc }
                $items += $ipItem
            }
        }
        else { Write-Verbose "Unknown location type: $($item.type)" }
    }

    return , $items
}

# ---------- Initialize and check result save file  ---------------
function Initialize-ResultSaveFile {
    param(
        [hashtable]$searchParams
    )

    if ([string]::IsNullOrEmpty($searchParams.resultFilePath)) { return $null }

    $absPath = $searchParams.resultFilePath
    $folder = Split-Path $absPath -Parent

    # create folder if necessary
    if (-not (Test-Path -LiteralPath $folder)) {
        try {
            $null = New-Item -Type Directory -Path $folder -ErrorAction Stop #PS2 fix
        }
        catch {
            return "Can not create folder $folder to save result"
        }
    }

    try {
        if (Test-Path -LiteralPath $absPath) {
            if ($searchParams.keepResults) { return $null }
            Remove-Item $absPath
        }

        Initialize-AutoSaveResultFile -absPath $absPath | Out-Null
        return $null

    }
    catch {
        return "Can not initialize the result file $($absPath): $($_.Exception.Message)" 
    }

    return $null
}

# ---------- Add columns header to result CSV file ------------
function Initialize-AutoSaveResultFile {
    param(
        [string]$absPath
    )
    $header = '"#";"File Path";"Size";"Date";"Content";"Rule"'
    Set-Content -Path $absPath -Value $header -Encoding utf8
}
