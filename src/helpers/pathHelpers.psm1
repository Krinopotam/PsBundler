
class PathHelpers {
    # Check if string is valid path (without file existence check)
    [bool]IsValidPath([string]$path) {
        try {
            [System.IO.Path]::GetFullPath($path)
            return $true
        }
        catch {
            return $false
        }
    }

    # returns full path (without file existence check). Returns empty string if path is not invalid
    [string]GetFullPath([string]$path) {
        try {
            return [System.IO.Path]::GetFullPath($path)
        }
        catch {
            return ""
        }
    }

    # returns full path  (without file existence check). Returns empty string if path is not invalid
    [string]GetFullPath([string]$path, [string]$basePath) {
        try {
            if ([System.IO.Path]::IsPathRooted($path)) {
                return [System.IO.Path]::GetFullPath($path)
            }

            $combined = [System.IO.Path]::Combine($basePath, $path)
            return [System.IO.Path]::GetFullPath($combined)
        }
        catch {
            return ""
        }
    }
}