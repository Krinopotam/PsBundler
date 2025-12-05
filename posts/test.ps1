$array = @("A", "B", "C")
Write-Host "Old items count: $($array.Count)"

Set-StrictMode -Version Latest

function Add-Item {
    param($item)
    
    if ($array) {
        Write-Host "Add item"
        $array += $item
    }
}

Add-Item "New Item"
Write-Host "New items count: $($array.Count)"