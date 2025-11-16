# ---------- Get host shares (compatible with powershell 2) -------------------------
function Get-HostShares {
    param (
        [string]$hostName
    )

    try {
        $output = net view "\\$hostName" /All 2>$null

        $shares = @()
        $parsing = $false
        foreach ($line in $output) {
            if ($line -match '^---+$') {
                $parsing = $true
                continue
            }

            if (-not $parsing) { continue }

            $line = $line.Trim()
            if ([string]::IsNullOrEmpty($line)) { continue }

            # Split by 2 or more spaces
            $parts = $line -split '\s{2,}'
        
            if ($parts.Length -lt 2) { continue }
            $name = $parts[0]
            $shares += $name
        }

        return , $shares
    }
    catch {
        return ,@()
    }
}

# ---------- Get host shared folders path ------------------------------------------
function Get-HostSharedFoldersPath {
    param (
        [string]$hostName
    )

    $shares = Get-HostShares $hostName
    $result = @()
    foreach ($share in $shares) {
        $result += "\\$hostName\$share"
    }
    if ($result.Count -gt 0) { $result += "\\$hostName\dfs" }

    return , $result
}

# ---------- Invoke net use ------------------------------------------
# 86 - wrong password
# 121  - timeout
function Invoke-NetUse {
    param(
        [string]$path,
        [string]$username,
        [string]$pass
    )

    $output = (net use $path /user:$username $pass 2>&1)

    $lines = $output -split "`r?`n"
    foreach ($line in $lines) {
        if ($line -match '\b(\d{2,4})\b') {
            return [int]$Matches[1]
        }
    }

    return 0
}