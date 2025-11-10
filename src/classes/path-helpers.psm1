
class PathHelpers {
    [bool]IsValidPath([string]$path) {
        try {
            [System.IO.Path]::GetFullPath($path) | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
}