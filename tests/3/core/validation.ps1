. "$PSScriptRoot/../helpers/strings.ps1"

# ---------- Check that at least one location is set ----------------
function Test-IsLocationsValid {
    param (
        [hashTable[]]$locations
    )
    if (-not $locations -or $locations.Count -eq 0) { return "There are no search locations set" }

    foreach ($loc in $locations) {
        if (-not $loc.Type) { return "Location type is empty for location: $($loc.Value)" }
        if ($loc.Type -ine "Folder" -and $loc.Type -ine "Ip range" -and $loc.Type -ine "Host") { return "Unknown location type: $($loc.Type)" }

        if (-not $loc.Value) { return "No location specified for location type: $($loc.Type)" }
        
        if ($loc.Type -ieq "Ip range") {
            $parts = Split-IpRangeToParts $loc.Value
            if ($null -eq $parts) { return "Invalid IP range: $($loc.Value)" }
            $ipErr = Test-IsValidIpRange -startIp $parts.startIp -endIp $parts.endIp
            if ($ipErr) { return $ipErr }
        }
        elseif ($loc.Type -ieq "Host") {
            $hostErr = Test-IsValidHostName -hostname $loc.Value
            if ($hostErr) { return $hostErr }
        }
    }

    return $null
}

function Test-IsSearchPatternsValid {
    param (
        [hashTable[]]$searchPatterns
    )
    if (-not $searchPatterns -or $searchPatterns.Count -eq 0) { return "There are no search patterns set" }

    foreach ($p in $searchPatterns) {
        if (-not $p.Type) { return "Pattern type is empty for pattern: $($p.Pattern)" }
        if ($p.Type -ine "Content" -and $p.Type -ine "Filename") { return "Unknown pattern type: $($p.Type)" }

        if (-not $p.Pattern) { return "No pattern specified for pattern type: $($p.type)" }
        if (-not (Test-RegexPattern -pattern $p.Pattern)) { return "Invalid regexp pattern: $($p.Pattern)" }
    }

    return $null
}

function Test-IsMaxFileSizeValid {
    param (
        [string]$maxFileSize
    )
    if ([string]::IsNullOrEmpty($maxFileSize)) { return $null }

    $size = Convert-ToBytes -size $maxFileSize
    if ($null -eq $size -or $size -lt 0) { return "Invalid max file size: $maxFileSize" }

    return $null
}

function Test-IsEncodingsValid {
    param (
        [string[]]$encodings
    )

    if (-not $encodings -or [string]::IsNullOrEmpty($encodings)) { return "No encodings specified" }
    $encodingArr = Split-StringToEncodings -encodings $encodings
    if ($encodingArr.Count -eq 0) { return "No valid encodings specified" }

    return $null
}

# ---------- Validate parameters before search ----------------
function Test-IsAllParamsValid {
    param (
        [hashtable]$params
    )

    $err = Test-IsLocationsValid -locations $params.locations
    if ($err) { return $err }   

    $err = Test-IsSearchPatternsValid -searchPatterns $params.searchPatterns
    if ($err) { return $err }   

    $err = Test-IsMaxFileSizeValid -maxFileSize $params.maxFileSize
    if ($err) { return $err }   

    $err = Test-IsEncodingsValid -encodings $params.encodings
    if ($err) { return $err }   

    return $null
}
