. "$PSScriptRoot/fileReader.ps1"
. "$PSScriptRoot/searchPrepare.ps1"
. "$PSScriptRoot/searchRegex.ps1"
. "$PSScriptRoot/validation.ps1"
. "$PSScriptRoot/../parsers/word.ps1"
. "$PSScriptRoot/../parsers/excel.ps1"
. "$PSScriptRoot/../parsers/zip.ps1"
. "$PSScriptRoot/../parsers/outlook.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/../helpers/net.ps1"


function Invoke-SearchProcess {
    param (
        [hashtable]$searchParams,
        [boolean]$resume = $false
    )

    Write-DebugLog "Invoke-SearchProcess function start"    

    $resumeData = $null
    if (-not $resume) { 
        $searchParams.appContext.session.locationValue = $null
        $searchParams.appContext.session.locationType = $null
        $searchParams.appContext.session.filePath = $null
        $searchParams.appContext.session.visitedPaths = @{}
    }
    elseif ($searchParams.appContext.session.locationValue -and $searchParams.appContext.session.locationType -and $searchParams.appContext.session.filePath) {
        $resumeData = @{
            locationValue = $searchParams.appContext.session.locationValue
            locationType  = $searchParams.appContext.session.locationType
            filePath      = $searchParams.appContext.session.filePath
        }
    }

    
    $setStatusText = $searchParams.setStatusText
    $onSearchStart = $searchParams.onSearchStart
    $onSearchStop = $searchParams.onSearchStop

    $resumed = $false

    $searchParams.appContext.state = "running"
    if ($onSearchStart) { &$onSearchStart }

    if ($resumeData) { &$setStatusText "Resuming search from: $($resumeData.filePath)" }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resumed = Invoke-LocationsIteration -searchParams $searchParams -resumeData $resumeData
    if ($resumed) { $resumeData = $null }
    $sw.Stop()

    if ($searchParams.appContext.state -eq "running") { 
        $searchParams.appContext.state = "completed" 
        
        if (-not $resumeData) {
            $searchParams.appContext.session.locationValue = $null
            $searchParams.appContext.session.locationType = $null
            $searchParams.appContext.session.filePath = $null
            $searchParams.appContext.session.visitedPaths = @{}
        }
    }
    
    if ($onSearchStop) { 
        if ($resumeData -and $searchParams.appContext.state -eq "completed") {
            &$onSearchStop "Failed to resume search from: $($resumeData.filePath)"
        }
        else {
            $time = Format-SecondsToReadableTime -seconds $sw.Elapsed.TotalSeconds
            $msg = "Search completed in $time"
            if ($searchParams.appContext.state -eq "stopped") { $msg = "Search stopped at $($searchParams.appContext.session.filePath) after $time" }
            &$onSearchStop $msg
        }
    }
    
    Write-DebugLog "Invoke-SearchProcess function end"
}

function Invoke-LocationsIteration {
    param ( 
        [hashtable]$searchParams,
        [hashtable]$resumeData = $null
    )

    $resumed = $false

    foreach ($loc in $searchParams.locations) {
        if ($searchParams.appContext.state -ne "running") { return $resumed }

        $locType = $loc.type.ToLower()

        if ($resumeData) {
            if ($resumeData.locationValue -ne $loc.value -or $resumeData.locationType -ne $locType) { continue }
        }
        else {
            $searchParams.appContext.session.locationValue = $loc.value
            $searchParams.appContext.session.locationType = $locType
        }

        if ($locType -eq "folder") {
            $resumed = Invoke-FoldersIteration -searchParams $searchParams -rootFolder $loc.value -resumeData $resumeData
            if ($resumed) { $resumeData = $null }
        }
        elseif ($locType -eq "host") {
            &$searchParams.setStatusText "Host: $($loc.value)"
            $foldersPath = Get-HostSharedFoldersPath -hostName $loc.value
            foreach ($folderPath in $foldersPath) {
                $resumed = Invoke-FoldersIteration -searchParams $searchParams -rootFolder $folderPath -resumeData $resumeData
                if ($resumed) { $resumeData = $null }
            }
        }
    }

    return $resumed
}


function Invoke-FoldersIteration {
    param (
        [hashtable]$searchParams,
        [string]$rootFolder,
        [hashtable]$resumeData = $null
    )

    if ($searchParams.appContext.state -ne "running") { return }

    $foldersStack = New-Object System.Collections.Stack
    $foldersStack.Push($rootFolder)

    Write-DebugLog "Invoke-FoldersIteration function start"

    while ($foldersStack.Count -gt 0) {
        if ($searchParams.appContext.state -ne "running") { return }

        $folderPath = $foldersStack.Pop()
        $visitedPaths = $searchParams.appContext.session.visitedPaths
       
        if ($resumeData) {
            $dirInPath = Test-DirInPath -filePath $resumeData.filePath -dirPath $folderPath 
            if (-not $dirInPath) { continue }
        }
        else {
            &$searchParams.setStatusText "Folder: $folderPath"
            Write-DebugLog "Folder: $folderPath"
        }


        try {
            $items = @(Get-ChildItem -Path $folderPath -Force -ErrorAction SilentlyContinue) # Force assert to array, because Get-ChildItem can return file instead of array for single item
                    
            # put child dirs to stack
            for ($i = $items.Count - 1; $i -ge 0; $i--) {
                $dir = $items[$i]
                if ((-not $dir.PSIsContainer) -or ($null -eq $dir) -or ($null -eq $dir.FullName)) { continue }
                $dirName = $dir.FullName.Trim()
                if ($dirName -eq "" -or $dirName -eq "." -or $dirName -eq "..") { continue }

                #if ($resumeData -and -not (Test-DirInPath -filePath $resumeData.filePath -dirPath $dirName)) { continue }

                $foldersStack.Push($dir.FullName)
            }

            #if ($visitedPaths.ContainsKey($folderPath)) { continue }

            if ($resumeData -and -not (Test-DirIsFileParent -filePath $resumeData.filePath -dirPath $folderPath)) { continue }

            # process files
            foreach ($item in $items) {
                if ($searchParams.appContext.state -ne "running") { return }
                if ($item.PSIsContainer) { continue }
                
                if ($resumeData) { 
                    if ($resumeData.filePath -eq $item.FullName) { $resumeData = $null }
                    continue
                }
                else {
                    $searchParams.appContext.session.filePath = $item.FullName
                }
                
                Invoke-ProcessFile -searchParams $searchParams -file $item
            }

            $visitedPaths[$folderPath] = $true
        }
        catch {
            &$searchParams.setStatusText "Can't read: $folderPath"
            Write-DebugErrorLog $_
            continue
        }
    }

    Write-DebugLog "Invoke-FoldersIteration function end"

    return ($null -eq $resumeData)
}

function Invoke-ProcessFile {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file
    )

    if ($searchParams.appContext.state -ne "running") { return }
    if ($null -eq $file) { continue }
            
    &$searchParams.setStatusText "File: $($file.FullName)"

    try {
        $fileDate = $file.LastWriteTime
        if ($searchParams.fileDateStart -and $fileDate -lt $searchParams.fileDateStart) { return }
        if ($searchParams.fileDateEnd -and $fileDate -gt $searchParams.fileDateEnd) { return }

        # --- Process filename patterns ----------
        Invoke-ProcessFileNameSearch -searchParams $searchParams -file $file | Out-Null
                
        # --- Process file content patterns ------
        if (Test-FileContentSearchSkip -searchParams $searchParams -fileName $file.Name -extension $file.Extension -fileSize $file.Length -fileDate $fileDate) { 
            if ($searchParams.setStatusText) { &$searchParams.setStatusText "Skipped: $($file.FullName)" }
            return 
        }

        Invoke-ProcessFileContentSearch -searchParams $searchParams -file $file | Out-Null
    }
    catch {
        &$searchParams.setStatusText "Can't parse: $($file.FullName)"
        Write-DebugErrorLog $_
    }
}

function Invoke-ProcessFileNameSearch {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file
    )

    $null = Test-FileNameForPatterns -searchParams $searchParams -fileName $file.Name -fileSize $file.Length -fileDate $file.LastWriteTime -filePath $file.FullName
}

function Invoke-ProcessFileContentSearch {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    Write-DebugLog "Invoke-ProcessFileContentSearch: $($file.FullName)"
    
    if (Test-IsZip -file $file) { Search-InZip -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches }
    elseif (Test-IsWordDoc -file $file) { Search-InWordDoc -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches }
    elseif (Test-IsExcel -file $file) { Search-InExcel -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches }
    elseif (Test-IsMsg -file $file) { Search-InMsg -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches }
    else {
        $null = Read-FileAtOnce -searchParams $searchParams -file $file
        #$null = Read-FileSimpleMethod -searchParams $searchParams -file $file
    }
}


