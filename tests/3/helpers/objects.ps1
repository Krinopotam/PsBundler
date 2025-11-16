
# Returns array of unique strings
function Get-UniqueStringValuesArray {
    param (
        [string[]]$Arr
    )   

    if (-not $Arr) { return ,@() }

    $dict = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($str in $Arr) {
        if ($dict.Contains($str)) { continue }
        #$dict.Add($str, $true)
        $dict[$str] = $true
    }
    return $dict.Keys
}

# Converts hashtable to PSObject
function Convert-HashtableToPSObject {
    param (
        $hash # No type specified, because it can be ordered hashtable or simple hashtable (If we specify type, it will be overwritten)
    )
    $result = New-Object PSObject
    foreach ($key in $hash.Keys) {
        $result | Add-Member -MemberType NoteProperty -Name $key -Value $hash[$key]
    }
    return $result
}