. "$PSScriptRoot/../helpers/strings.ps1"

# ---------- Search string content for patterns ----------------
function Test-FileNameForPatterns {
    param (
        [hashtable]$searchParams,
        [string]$fileName,
        [string]$filePath,
        [long]$fileSize,
        [datetime]$fileDate,
        [hashtable]$deduplicatedMatches = @{},
        [string]$prefix = "",
        [string]$postfix = ""
    )

    $patterns = $searchParams.filenamePatterns

    foreach ($p in $patterns) {
        if ($searchParams.appContext.state -ne "running") { return }
        if ($null -ne $p.MinFileSize -and $fileSize -lt $p.MinFileSize) { continue }
        if ($null -ne $p.MaxFileSize -and $fileSize -gt $p.MaxFileSize) { continue }

        $resultMatches = [regex]::Matches($fileName, $p.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        if ($resultMatches.Count -lt 1) { continue }

        $result = "$prefix[Filename match]: $($resultMatches[0].Value)$postfix"

        if ($deduplicatedMatches.ContainsKey($result)) { continue }
        $deduplicatedMatches.Add($result, $null)

        $values = New-Object System.Collections.Specialized.OrderedDictionary
        $values.Add("#", 0)
        $values.Add("FilePath", $filePath)
        $values.Add("FileSize", $fileSize)
        $values.Add("FileDate", $fileDate)
        $values.Add("Content", $result)
        $values.Add("RuleDesc", $p.desc)

        &$searchParams.addToResult -searchParams $searchParams -values $values | Out-Null
        return 
    }
}

# Check, if content search should be skipped
function Test-FileContentSearchSkip {
    param (
        [hashtable]$searchParams,
        [string]$fileName,
        [string]$extension,
        [long]$fileSize,
        [datetime]$fileDate # for future purposes
    )

    if (-not $fileSize) {return $true}
    if ($null -ne $searchParams.maxFileSize -and $fileSize -gt $searchParams.maxFileSize) {return $true}
    if (-not (Test-FileNameMaskMatch -fileName $fileName -extension $extension -masks $searchParams.allowedMasks)) {return $true}
    if (Test-FileNameMaskMatch -fileName $fileName -extension $extension -masks $searchParams.excludedMasks) {return $true}

    return $false
}

function Test-ContentForPatterns {
    param (
        [hashtable]$searchParams,
        [string]$content,
        [string]$filePath,
        [string]$fileName,
        [long]$fileSize,
        [datetime]$fileDate,
        [hashtable]$deduplicatedMatches,
        [string]$prefix = "",
        [string]$postfix = ""
    )

    # Be aware, $filePath and $fileName may belong to different files in case of nested zip. $filePath is zip-file path (to show in result grid), but $fileName is file name in zip

    if ([string]::IsNullOrEmpty($content)) { return }

    $extension = [System.IO.Path]::GetExtension($fileName)

    $patterns = $searchParams.contentPatterns

    foreach ($p in $patterns) {
        if ($searchParams.appContext.state -ne "running") { return }

        if ($null -ne $p.MaxContentLength -and $content.Length -gt $p.MaxContentLength) { continue }
        if ($p.IncludedMasks -and -not (Test-FileNameMaskMatch -fileName $fileName -extension $extension -masks $p.IncludedMasks)) { continue }
        if ($p.ExcludedMasks -and (Test-FileNameMaskMatch -fileName $fileName -extension $extension -masks $p.ExcludedMasks)) { continue }

        $resultMatches = Search-ByRegexpPattern -text $content -pattern $p.Pattern
        if (-not $resultMatches) { continue }

        $matchCount = 0
        foreach ($m in $resultMatches) {
            $matchCount++
            if ($matchCount -ge 10) { break } # Limit match output for each file

            $headText = Get-SearchResultHead -searchParams $searchParams -content $content -match $m
            $trailingText = Get-SearchResultTrail -searchParams $searchParams -content $content -match $m

            $val = $m.Value -replace '(\r?\n)+', "`r`n"
            $result = "$prefix$headText$val$trailingText$postfix"
            if ($result.Length -gt 200) {
                $result = $result.Substring(0, 200)
            }

            if ($deduplicatedMatches.ContainsKey($result)) { continue }
            $deduplicatedMatches.Add($result, $null)

            $values = New-Object System.Collections.Specialized.OrderedDictionary
            $values.Add("#", 0)
            $values.Add("FilePath", $filePath)
            $values.Add("FileSize", $fileSize)
            $values.Add("FileDate", $fileDate)
            $values.Add("Content", $result)
            $values.Add("RuleDesc", $p.desc)

            &$searchParams.addToResult -searchParams $searchParams -values $values | Out-Null
        }
    }
}

function Get-SearchResultHead {
    param (
        [hashtable]$searchParams,
        [string]$content,
        [System.Text.RegularExpressions.Match]$match
    )

    $result = ""
    $headLength = $searchParams.searchResultHead
    if (-not $headLength -or $match.Index -le 0) { return $result }

    $length = $headLength
    $dots = "..."
    if ($match.Index -le $headLength) {
        $length = $match.Index
        $dots = ""
    }
    $startIdx = $match.Index - $length

    $result = $content.Substring($startIdx, $length)#.Replace("`r", "").Replace("`n", " ")
    return "$dots$result"
}

function Get-SearchResultTrail {
    param (
        [hashtable]$searchParams,
        [string]$content,
        [System.Text.RegularExpressions.Match]$match
    )

    $result = ""
    $trailLength = $searchParams.searchResultTrail
    if (-not $trailLength) { return $result }

    $startIdx = $match.Index + $match.Length
    if ($startIdx -ge $content.Length) { return $result }

    $length = $trailLength
    $dots = "..."
    if (($content.Length - $startIdx) -le $trailLength) {
        $length = $content.Length - $startIdx
        $dots = ""
    }

    $result = $content.Substring($startIdx, $length)#.Replace("`r", "").Replace("`n", " ")
    return "$result$dots"
}