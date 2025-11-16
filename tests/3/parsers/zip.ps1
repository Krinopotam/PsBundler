. "$PSScriptRoot/../core/fileReader.ps1"
. "$PSScriptRoot/../core/searchRegex.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"

# ---------- Check if file is zip ------------------------------
function Test-IsZip {
    param (
        [System.IO.FileInfo]$file,
        [boolean]$strict = $false
    )

    if ($file.Extension.ToLower() -ne ".zip") { return $false }

    if (-not $strict) { return $true }
    return Test-ZipHeader -file $file
}

# ---------- Check if file has zip header ----------------------
function Test-ZipHeader {
    param (
        [System.IO.FileInfo]$file
    )

    $zipHeader = [byte[]](0x50, 0x4B, 0x03, 0x04)  # PK

    $fs = New-Object System.IO.FileStream (
        $file.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    $buffer = New-Object byte[] 4
    $bytesRead = $fs.Read($buffer, 0, 4)
    $fs.Close()

    if ($bytesRead -ne 4) { return $false }
    
    for ($i = 0; $i -lt 4; $i++) {
        if ($buffer[$i] -ne $zipHeader[$i]) {
            return $false
        }
    }

    return $true
}

# ---------- Search string content for patterns in zip file -----------
function Search-InZip {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file, 
        [hashtable]$deduplicatedMatches = @{}
    )

    $queue = New-Object System.Collections.Queue
    
    $rootZip = $null
    $rootStream = $null 

    try {
        $rootStream = New-Object System.IO.FileStream (
            $file.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $rootZip = New-Object System.IO.Compression.ZipArchive ($rootStream, [System.IO.Compression.ZipArchiveMode]::Read)

        $queue.Enqueue(@{
                zip        = $rootZip
                stream     = $rootStream
                nestedPath = ""
            })

        $allErrors = $true
        while ($queue.Count -gt 0) {
            $zipInfo = $queue.Dequeue()

            foreach ($entry in $zipInfo.zip.Entries) {
                $entryStream = $null
                $ms = $null
            
                try {
                    $entryFullName = $entry.FullName
                    $entryName = $entry.Name

                    if (Test-IsBrokenEncoding $entryFullName) { 
                        $entryFullName = Convert-Cp866ToCp1251 $entryFullName 
                        $entryName = Convert-Cp866ToCp1251 $entryName
                    }

                    $entryExtension = ([System.IO.Path]::GetExtension($entryName)).ToLower()
                    
                    if ($entryFullName.EndsWith("/")) { continue }

                    $deduplicatedMatches = @{}
                    $postfix = "`r`n[ZIP$($zipInfo.nestedPath)/$entryFullName]"

                    $fileDate = $entry.LastWriteTime.DateTime

                    if ($searchParams.fileDateStart -and $fileDate -lt $searchParams.fileDateStart) { continue }
                    if ($searchParams.fileDateEnd -and $fileDate -gt $searchParams.fileDateEnd) { continue }

                    $null = Test-FileNameForPatterns -searchParams $searchParams -fileName $entryFullName -filePath $file.FullName -fileSize $entry.Length -fileDate $fileDate -postfix $postfix -deduplicatedMatches $deduplicatedMatches
                
                    if ($entryExtension -ne ".zip") {
                        if (Test-FileContentSearchSkip -searchParams $searchParams -fileName $entryName -extension $entryExtension -fileSize $entry.Length -fileDate $fileDate) { 
                            continue            
                        }
                    }

                    $entryStream = $entry.Open() 
                    $ms = New-Object System.IO.MemoryStream
                    $entryStream.CopyTo($ms)
                    $entryStream.Dispose()
                    $ms.Position = 0
                    $allErrors = $false

                    if ($entryExtension -ne ".zip") {
                        # Search in file content. Be aware, filePath is zip-file path, but fileName is file name in zip
                        Read-StreamContent -stream $ms -searchParams $searchParams -filePath $file.FullName -fileName $entryName -fileSize $entry.Length -fileDate $entry.LastWriteTime.DateTime -postfix $postfix
                        $ms.Dispose()
                        $ms = $null
                        continue
                    }
            
                    $nestedZip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)
                    $queue.Enqueue(@{
                            zip        = $nestedZip
                            stream     = $ms
                            nestedPath = $zipInfo.nestedPath + '/' + $entryName
                        })
                    $ms = $null
                }
                catch {
                    Write-DebugErrorLog $_
                    if ($ms) { $ms.Dispose() }
                    if ($entryStream) { $entryStream.Dispose() }
                }
            }

            $zipInfo.zip.Dispose()
            if ($zipInfo.stream) { $zipInfo.stream.Dispose() }
        }

        if ($allErrors) { 
            #seems that file is password protected
            $values = New-Object System.Collections.Specialized.OrderedDictionary
            $values.Add("#", 0)
            $values.Add("FilePath", $file.FullName)
            $values.Add("FileSize", $file.Length)
            $values.Add("FileDate", $file.LastWriteTime)
            $values.Add("Content", "[Password protected]")
            $values.Add("RuleDesc", "")
            &$searchParams.addToResult -searchParams $searchParams -values $values | Out-Null
        }
         
        return $true
    }
    catch {
        Write-DebugErrorLog $_
    }
    finally {
        if ($rootZip) { $rootZip.Dispose() }
        if ($rootStream) { $rootStream.Dispose() }
    }
    return $false
}