function Search-ByRegexpPattern {
    param (
        [string]$text,
        [string]$pattern
    )
    if ($pattern -eq "") { return $null }
    try {
        $resultMatches = [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline) 
        return $resultMatches
    }
    catch {
        return $null
    }
}

# ---------- Check is RegExp pattern has no errors -------------
function Test-RegexPattern {
    param (
        [string]$pattern
    )

    try {
        #$null = [regex]::new($pattern)
        $null = New-Object regex $pattern #PS2 Fix
        return $true
    }
    catch {
        return $false
    }
}

# ---------- Convert string to integer. Returns null if error --
function Convert-ToInt {
    param (
        [string]$str
    )
    
    [int]$result = 0
    if ([int]::TryParse($str, [ref]$result)) { return $result }
    else { return $null }
}

# ---------- Convert string to long. Returns null if error --
function Convert-ToLong {
    param (
        [string]$str
    )
    
    [long]$result = 0
    if ([long]::TryParse($str, [ref]$result)) { return $result }
    else { return $null }
}

function Convert-ToBoolean {
    param (
        [string]$str
    )

    try {
        $str = $str.Trim().ToLower()
        if ($str -eq "true" -or $str -eq "1") { return $true }
        if ($str -eq "false" -or $str -eq "0") { return $false }
        return [bool]$str
    }
    catch {
        return $false
    }
}

function Convert-ToDateTime {
    param (
        [object]$val
    )

    if (-not $val) { return $null }

    if ($val -is [datetime]) { return $val }

    try {
        if ($val -match '^\d{4}$') { $val = "$val-01-01" }
        
        $dt = [datetime]::Parse($val)
        if ($dt.Year -ge 1900 -and $dt.Year -le 2999) { return $dt }
        else { return $null }
    }
    catch {
        return $null
    }
}

# ---------- Convert string to bytes. Returns null if error --
function Convert-ToBytes {
    param (
        [string]$size
    )

    $multipliers = @{
        B  = 1
        KB = 1KB
        MB = 1MB
        GB = 1GB
        TB = 1TB
    }

    $size = $size.Trim().ToUpper()
    
    if ($size -match '^(\d+(?:[.,]\d+)?)\s*([KMGT]?B)$') {
        $number = $matches[1] -replace ',', '.' # for support comma as decimal separator
        $unit = $matches[2]
        if ($multipliers.ContainsKey($unit)) {
            return [math]::Round([double]$number * $multipliers[$unit])
        }
        
        return $null
    }
    else {
        return Convert-ToInt -str $size
    }
}

# ---------- Check if string is valid IP address (even if string is integer) ----------------
function Test-IsValidIp {
    param (
        [string]$str
    )

    # we dont use [System.Net.IPAddress]::Parse() because it has compatibility issues in powershell v2

    $dotted = Test-IsIpAddress $str
    if ($dotted) { return $true }
    
    # trying to recognize as integer from 0 to 4294967295
    try {
        $num = [uint32]$str
        if ($num -ge 0 -and $num -le 4294967295) { return $true }
    }
    catch {}

    return $false
}

# ---------- Check if string is valid IP address (octets only) ----------------
function Test-IsIpAddress {
    param (
        [string]$str
    )

    if ( $str -match '^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$') { return $true }
    
    return $false
}

# ---------- Check if string is valid host name ----------------
function Test-IsStringCanBeHostName {
    param (
        [string]$str
    )

    if ($str.Length -lt 1 -or $str.Length -gt 253) { return $false }

    # Check NetBIOS or DNS name
    if (-not ($str -match '^(?!\-)([a-zA-Z0-9_\-]{1,63})(\.([a-zA-Z0-9_\-]{1,63}))*$')) { return $false }

    return $true
}


# ---------- Check if strings is valid IP range ---------------
function Test-IsValidIpRange {
    param (
        [string]$startIp,
        [string]$endIp
    )
    
    if (-not (Test-IsValidIp $startIp)) { return "Invalid start IP address: $startIp" }
    if (-not (Test-IsValidIp $endIp)) { return "Invalid end IP address: $endIp" }

    # Convert to uint32
    $startInt = Convert-IPToUint $startIp
    $endInt = Convert-IPToUint $endIp

    if ($startInt -gt $endInt) { return "Start IP $startIp is greater than end IP $endIp" }

    if ($endInt - $startInt -gt 10000) { return "IP range is too large: $($endInt - $startInt) addresses" }

    return $null
}

function Test-IsValidHostName {
    param (
        [string]$hostName
    )

    if (-not (Test-IsStringCanBeHostName $hostName) -and -not (Test-IsIpAddress $hostName)) { return "Invalid host name or IP: $hostName" }
    return $null
}

# ---------- Get normalized IP address (strip leading zeros and convert from integer ) ----------------
function Get-NormalizedIp {
    param (
        [string]$str
    )

    # If it is already in the format x.x.x.x, check and return, possibly removing leading zeros
    if (Test-IsIpAddress $str) {
        $parts = $str.Split('.') | ForEach-Object { [int]$_ }
        return ($parts -join '.')
    }

    # Trying to recognize as integer from 0 to 4294967295
    try {
        $n = [uint32]$str
        if ($n -lt 0 -or $n -gt 4294967295) { throw "Out of range" }

        $b1 = [math]::Floor($n / 16777216)
        $remainder = $n % 16777216

        $b2 = [math]::Floor($remainder / 65536)
        $remainder = $remainder % 65536

        $b3 = [math]::Floor($remainder / 256)
        $b4 = $remainder % 256

        return "$b1.$b2.$b3.$b4"
    }
    catch {
        throw "Invalid IP address: $str"
    }
}


# ---------- Get IP ranges from start and end IP addresses (You should validate them first) -------
function Get-IpRangesList {
    param (
        [string]$startIp,
        [string]$endIp
    )

    # Convert to uint32
    $startInt = Convert-IPToUint $startIp
    $endInt = Convert-IPToUint $endIp

    $result = @()
    for ($i = $startInt; $i -le $endInt; $i++) {
        # compatible with powershell v2
        $b1 = [math]::Floor($i / 16777216)       # 2^24
        $b2 = [math]::Floor(($i % 16777216) / 65536)
        $b3 = [math]::Floor(($i % 65536) / 256)
        $b4 = $i % 256
        $result += "$b1.$b2.$b3.$b4"
    }

    return , $result
}

# ---------- Convert IP address bytes to uint32 ----------------
function Convert-IPToUint {
    param (
        [string]$ipOrInt
    )

    # Check if it is already uint32
    try {
        $asInt = [uint32]$ipOrInt
        return $asInt
    }
    catch {}

    # Check if it is dotted IP
    if (-not (Test-IsIpAddress $ipOrInt)) { throw "Invalid IP address format: $ipOrInt" }

    $parts = $ipOrInt.Split('.')
    if ($parts.Count -ne 4) { throw "Invalid IP: not 4 octets" }

    $b1 = [uint32]$parts[0]
    $b2 = [uint32]$parts[1]
    $b3 = [uint32]$parts[2]
    $b4 = [uint32]$parts[3]

    # Use only arithmetic (2.0 PowerShell does not like -shl and -bor)
    $result = ($b1 * 16777216) + ($b2 * 65536) + ($b3 * 256) + $b4
    return $result
}

# ---------- Split IP range to parts (parse 1.1.1.1-2.2.2.2/Folder to 1.1.1.1, 2.2.2.2, Folder) ----------------
function Split-IpRangeToParts {
    param (
        [string]$str
    )
    
    $ipRange = $str
    $folder = ""
    $index = $str.IndexOf('\')

    if ($index -ge 0) {
        $ipRange = $str.Substring(0, $index)
        $folder = $str.Substring($index)
    }

    $startIp = $ipRange
    $endIp = ""
    $index = $ipRange.IndexOf('-')
    
    if ($index -lt 0) { return $null }
    
    $startIp = $ipRange.Substring(0, $index).Trim()
    $endIp = $ipRange.Substring($index + 1).Trim()  

    return @{
        startIp = $startIp
        endIp   = $endIp
        folder  = $folder
    }
}


# ---------- Split string to array by separator ----------------
function Split-StringToArray {
    param (
        [string]$str,
        [string]$separator = ","
    )

    $str = $str.Trim()
    if (-not $str) { return , @() }

    $result = New-Object System.Collections.ArrayList

    $items = $str -split $separator

    foreach ($item in $items) {
        $trimmed = $item.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }
        $null = $result.Add($trimmed)
    }

    return , $result.ToArray() 
}

# ---------- Convert encoding encoding name to canonical name ----
function Get-CanonicalEncodingName {
    param (
        [string]$name
    )   

    $name = $name.ToLower()
    if ($name -eq "windows-1251" -or $name -eq "windows1251" -or $name -eq "win-1251" -or $name -eq "win1251" -or $name -eq "cp1251") { return "windows-1251" } 
    if ($name -eq "utf-8" -or $name -eq "utf8") { return "utf-8" }
    if ($name -eq "utf-16" -or $name -eq "utf16") { return "utf-16" }
    if ($name -eq "koi8-r" -or $name -eq "koi8r" -or $name -eq "koi8-ru" -or $name -eq "koi8") { return "koi8-r" }
    return ""
}

function Split-StringToEncodings {
    param (
        [string]$encodings
    )
    
    $encList = Split-StringToArray -str $encodings -separator ","

    $result = @()
    foreach ($enc in $encList) {
        $canonicalName = Get-CanonicalEncodingName -name $enc.ToLower()
        if ($canonicalName.Length -eq 0) { 
            Write-Verbose "Unknown encoding: $enc, skipping"
            continue 
        }
        $result += $canonicalName
    }

    return , $result
}

function Get-ErrorText {
    param(
        [System.Management.Automation.ErrorRecord]$err,
        [string]$prefix = "Error:"
    )
    $errorInfo = "$prefix
    Message: $($err.Exception.Message)
    Category: $($err.CategoryInfo.Category)
    Target: $($err.InvocationInfo.MyCommand)
    Script: $($err.InvocationInfo.ScriptName)
    Line: $($err.InvocationInfo.ScriptLineNumber)
    Position: $($err.InvocationInfo.OffsetInLine)
    StackTrace:
    $($err.ScriptStackTrace)"

    return $errorInfo
}

# Returns COM error code. PS 2 can not easily get COM error code, so we have to parse exception
function Get-ComErrorCode {
    param(
        [System.Management.Automation.ErrorRecord]$err
    )

    $ex = $err.Exception
    while ($ex) {
        if ($ex -is [System.Runtime.InteropServices.COMException]) {
            return $ex.ErrorCode
        }
        $ex = $ex.InnerException
    }

    return $null
}

function Test-IsBrokenEncoding {
    param (
        [string]$str
    )
    
    # Latin-1 characters with diacritics
    $latin1Garbage = '[\u00A0-\u00FF]'

    return $str -match $latin1Garbage
}

function Convert-Cp866ToCp1251 {
    param([string]$wrongName)
    $bytes = [System.Text.Encoding]::GetEncoding(1251).GetBytes($wrongName)
    return [System.Text.Encoding]::GetEncoding(866).GetString($bytes)
}


function Remove-SurroundingQuotes {
    param(
        [string]$Text
    )

    if (-not $Text) { return $Text }

    if ($Text.StartsWith('"') -and $Text.EndsWith('"') -and $Text.Length -ge 2) {
        return $Text.Substring(1, $Text.Length - 2)
    }

    if ($Text.StartsWith("'") -and $Text.EndsWith("'") -and $Text.Length -ge 2) {
        return $Text.Substring(1, $Text.Length - 2)
    }

    return $Text
}

# Try to get encoding by BOM
function Get-EncodingsByBomDetection {
    param(
        [byte[]]$Buffer
    )

    if ($Buffer.Length -ge 3 -and $Buffer[0] -eq 0xEF -and $Buffer[1] -eq 0xBB -and $Buffer[2] -eq 0xBF) {
        # UTF-8 BOM
        return (New-Object System.Text.UTF8Encoding $false)
    }
    elseif ($Buffer.Length -ge 2 -and $Buffer[0] -eq 0xFF -and $Buffer[1] -eq 0xFE) {
        # UTF-16 LE BOM
        return [System.Text.Encoding]::Unicode
    }
    elseif ($Buffer.Length -ge 2 -and $Buffer[0] -eq 0xFE -and $Buffer[1] -eq 0xFF) {
        # UTF-16 BE BOM
        return [System.Text.Encoding]::BigEndianUnicode
    }

    return $null
}

function Format-SecondsToReadableTime {
    param(
        [double]$seconds
    )

    $rounded = [Math]::Round($seconds, 2)
    $ts = [System.TimeSpan]::FromSeconds($rounded)

    $parts = @()

    if ($ts.Days -gt 0) { $parts += "$($ts.Days) $(Format-Unit $ts.Days 'day' 'days')" }
    if ($ts.Hours -gt 0) { $parts += "$($ts.Hours) $(Format-Unit $ts.Hours 'hour' 'hours')" }
    if ($ts.Minutes -gt 0) { $parts += "$($ts.Minutes) $(Format-Unit $ts.Minutes 'minute' 'minutes')" }

    $secs = $ts.Seconds + $ts.Milliseconds / 1000.0
    if ($parts.Count -eq 0 -or $secs -gt 0) { $parts += "$secs $(Format-Unit $secs 'second' 'seconds')" }    

    return ($parts -join " ")
}

function Format-Unit {
    param(
        [int]$value,
        [string]$singular,
        [string]$plural
    )
    if ($value -le 1) { return "$singular" }
    else { return "$plural" }
}

function Convert-ToBase64 {
    param(
        [string]$str
    )
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($str))
}

function Convert-FromBase64 {
    param(
        [string]$str
    )
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($str))
}