##########################################################################################
#Author: Zaytsev Maksim
#Version: 1.4.41
#requires -Version 2.0
#recommended -Version 5.1
##########################################################################################

[CmdletBinding()]
param(
    [boolean]$gui = $true,

    [hashTable[]]$locations = @(
        @{ Type = 'Folder'; Value = 'd:\downloads'; Selected = $true }
        #@{ Type = 'Folder'; Value = $pwd.path },
        #@{ Type = 'IP Range'; Value = '244.178.44.111 - 244.178.44.115\C$' }
        #@{ Type = 'Host'; Value = 'msk.rn.ru' }
    ),

    [hashtable[]]$searchPatterns = @(
        @{ 
            Type     = 'Content'
            Pattern  = '\bsqlplus\s*[a-zа-яё0-9.#_-]+\/\S+'
            Desc     = 'Oracle SQLPlus credentials' 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '\bmysql\b.*?\s+-p\s?\S+'
            Desc     = 'MySQL command with password' 
            Selected = $true
        },
        @{
            Type     = 'Content'
            Pattern  = '\bmongo\b.*\s-p\s+\S+' 
            Desc     = 'MongoDB command with password' 
            Selected = $true
        },
        @{ Type      = 'Content'
            Pattern  = '\bredis-cli\b.*\s-a\s+\S+'
            Desc     = 'Redis CLI command with password' 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '\bnet\s{1,}user\s+[a-zа-яё0-9.#_-]+\s+\S{1,33}'
            Desc     = 'Windows “net user” password' 
            Selected = $true
        },
        @{
            Type     = 'Content'
            Pattern  = '\bschtasks\b.*?(?:/p|/rp)\s+\S{1,33}' 
            Desc     = 'Scheduled task password' 
            Selected = $true
        },
        @{ 
            Type     = 'Content' 
            Pattern  = '\bcurl\b.*?\s-u\s+\S+:\S{1,33}' 
            Desc     = 'Curl command with password' 
            Selected = $true
        },
        @{ 
            Type     = 'Content' 
            Pattern  = '\b(?!(?:mailto|smtp|e?-?mail|https?)\b)(?<=(?:^|[\s/\\]))[a-zа-я][a-zа-яё0-9.#_+-]{2,32}:[a-z0-9!#№$%^&*()_+\=\[\]{}\\|;''"",.<>\/?~`-]{1,32}@[a-z0-9#$_\-\[\]\\:.\/~]{4,32}'
            Desc     = 'Login:password@host pattern' 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '\bbearer[ ]*[:= ][ ]*[a-z0-9\-_\.]{10,}' 
            Desc     = 'Bearer/JWT token' 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '[''""]?(?<![a-z0-9_-])(?![a-z0-9_-]*public[a-z0-9_-]*token\b)[a-z-_]*token\b[''""]?\s*(?:value)?[:=> ]\s*[''""]?([a-z0-9_\-\.\/\+\=\~]{8,})[''""]?' 
            Desc     = 'Auth token' 
            Selected = $true
        },
        @{ 
            Type          = 'Content'
            Pattern       = '(?-m)^\s*[a-z0-9!@#№$%^&*()_+\-=\[\]{}\\|;''"",.<>\/?~`]{5,32}\s*$' 
            includedMasks = "*.txt, *.docx, *.docx"
            Desc          = 'Single line password file' 
            Selected      = $true
        },
        @{ 
            Type             = 'Content' 
            Pattern          = '(?-m)(?<=^|\r?\n\s*\r?\n)[a-zа-яё#@0-9\\/_ .-]{2,30}\r?\n((?=.*[a-z0-9])[a-z0-9!@#№$%^&*()_+\-=\[\]{}\\|;:''"",.<>\/?~]{6,32})(?=\r?\n\s*\r?\n|$|\r?\n$)' 
            includedMasks    = "*.txt, *.docx, *.docx"
            MaxContentLength = 10000
            Desc             = 'Login/password 2-line pair' 
            Selected         = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '(?:password|passwd|[a-z_-]+pass[0-9]?|pwd|auth[-_ ]?key|api[-_ ]?key|secret[-_ ]?key|private[-_ ]?key|site[-_ ]?key|private[-_ ]?line)[''""]?\s*(?:value)?\s*[/]?[=: >]\s*[''""]?\S{1,33}'
            Desc     = 'Secret assignment (password=value)' 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = '(?:логин\s|парол|кодовая|фраза|учетка|учетная запись|русскими буквами|- новый)' 
            Desc     = "User's password note" 
            Selected = $true
        },
        @{ 
            Type     = 'Content'
            Pattern  = 'коммерческая тайна|конфиденциально' 
            Desc     = "Confidential information note" 
            Selected = $true
        },
        @{ 
            Type     = 'Filename' 
            Pattern  = '(?:парол|password|учетка|логин|доступ|нужное|нужная|\bличное|\bличная|auth|credent|api[-_]?key|secret|private|site[-_]?key|новый текстовый документ|new text document|Документ Microsoft Word)'
            Desc     = 'Password-related file' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename' 
            Pattern  = '(?:passport|pasport|snils|voenn|pension|inn\b|паспорт|пенсион|инн\b|снилс|резюме|диплом|военны).*\.(pdf|png|jpg|jpeg|tiff|bmp|zip|rar)$' 
            Desc     = 'Personal documents' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename' 
            Pattern  = '^\d{1,12}(\.txt|$)' 
            Desc     = 'Numeric filename (like: 123.txt)' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename'
            Pattern  = '\.(crt|cer|pem|der|pfx|p12|p7b|p7c|spc|csr|key|dst)$' 
            Desc     = 'Certificate or key file' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename'
            Pattern  = '\.(tib|tibx|iso|img|vhd|vhdx|vmdk|dmg|vdi|xva)$' 
            Desc     = 'Disk image or backup' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename' 
            Pattern  = '^(?:xmrig|xmrig-proxy|xmrigcc|xmr-stak|t-?rex|trexminer-pro|nbminer|gmine?r?|teamredminer|phoenixminer|lolminer|cryptodredge|bminer|cudominer|ethdcrminer64|ethminer|cpuminer|cpuminer-multi|minerd|cgminer|bfgminer|kawpowminer|multi-?miner|miner|ergominer|ravencoinminer)(?:[-_.\s]?v?\d+(?:\.\d+)*)?(?:[-_.\s]?(?:64|x64|amd64))?(?:\.(?:exe|bat|cmd|ps1|sh|run|bin|out|app|zip|tar|tar\.gz|tgz|7z|rar))?$'
            Desc     = 'Miners' 
            Selected = $true
        },
        @{ 
            Type     = 'Filename' 
            Pattern  = '^(\.htpasswd|htpasswd|\.pgpass|mysql\.conf|\.my\.cnf|users\.xml|passwd|shadow|\.netrc|\.env[-.]?(?:bak|back)?)$' 
            Desc     = 'Critical auth/config file' 
            Selected = $true
        },
        @{ 
            Type    = 'Filename' 
            Pattern = '^(?!(?:package\.json|package-lock\.json|tsconfig\.json|pom\.xml|php\.ini|desktop\.ini|default\.ini|autorun\.ini)$).*\.(ini|cfg|cnf|conf|config|json|yml|yaml|xml|properties|env)$'
            Desc    = 'General config file' 
        },
        @{ 
            Type    = 'Filename' 
            Pattern = '^(?!thumbs\.db$).*\.(mdb|accdb|db|sqlite|sqlite3|db3|sdb|mdf|dbf|dbase|ibd|myd|myi|dump)$' 
            Desc    = 'Database file' 
        }
    ),

    #[string]$allowedMasks = '*.me, *.txt, *.log, *.conf, *.sql, *.ini, *.cmd, *.bat, *.sh, *.config, *.etc, *.env, *.ps1, *.vb, *.vbs, *.cs, *.json, *.yaml, *.yml, *.xml, *.properties, *.toml, *.reg, *.pl, *.py, *.rb, *.go, *.ts, *.js, *.cjs, *.mjs, *.key, *.asc, *.credentials, *.vault, *.out, *.err, *.mobileconfig, *.plist, *.tfvars',
    [string]$allowedMasks = '*.*',

    [string]$excludedMasks = '*.bin, *.cab, *.dll, *.exe, *.lib, *.msi, *.msm, *.mst, *.ocx, *.pak, *.rll, *.so, *.sys, *.wcx, ' + `
        '*.7zip, *7z, *.gz, *.iso, *.rar, ' + `
        '*.dot, *.pdf, *.pptp, *.pptx, ' + `
        '*.chm, *.dat, *.md, *.lng, *.mui, *.url, ' + `
        '*.otf, *.ttf, ' + `
        '*.bmp, *.gif, *.ico, *.jpeg, *.jpg, *.png, *.tif, *.tiff, ' + `
        '*.avi, *.mkv, *.mov, *.mp4, ' + `
        '*.acc, *.flac, *.wmv, *.mp3, *.wav, ' + `
        '*.apk, *.bpl, *.class, *.css, *.htm, *.html, *.jar, *.pyd, *.pyc, *.opa, *.opal, *.swf, *.wasm, ' + `
        '*.utm',

    [string]$maxFileSize = '3mb',

    #[string]$encodings = 'windows-1251, utf-8, utf-16, koi8-r, utf-16',
    [string]$encodings = 'windows-1251, utf-8',

    [string]$resultFilePath = 'autosaved-results.csv',

    # Add 5 chars before found text
    [int]$searchResultHead = 10, 

    # Add 15 chars after found text
    [int]$searchResultTrail = 15,

    [string]$fileDateStart = "",
    
    [string]$fileDateEnd = ""
)

$script:APP_NAME = "Regexp Search Tool"
$script:APP_VERSION = "1.4.39"

Set-StrictMode -Version 2

. "$PSScriptRoot/core/requirements.ps1"
. "$PSScriptRoot/core/search.ps1"
. "$PSScriptRoot/core/handlers.ps1"
. "$PSScriptRoot/core/initConsoleSearch.ps1"
. "$PSScriptRoot/gui/initForm.ps1"
. "$PSScriptRoot/parsers/outlook.ps1"
. "$PSScriptRoot/parsers/word.ps1"
. "$PSScriptRoot/parsers/excel.ps1"

#$DebugPreference = 'Continue'
#$VerbosePreference = 'Continue'

# ---------- Globals -------------------------------------------
$script:APP_CONTEXT = [hashtable]::Synchronized(@{
        # Application running state    
        state      = "idle" # "running", "finished", "stopped", "exit" 

        # GUI mode
        gui        = $gui

        # Total found results count
        totalFound = 0

        # Supported features
        features   = @{
            "zip"     = $true
            "outlook" = $true
            "word"    = $true
            "excel"   = $false # Excel com is no stable. Will use default zip parser
        }

        # Current session data
        session    = @{
            locationValue = $null
            locationType  = $null
            filePath      = $null
            visitedPaths  = @{}
            unsaved       = $false
        } 
    })

# Runspace context
$script:RS_CONTEXT = [hashtable]::Synchronized(@{
        ps = $null
        rs = $null
    })

# Logging to screen, not to file
$script:LOG_TO_SCREEN = $false

# ---------- Start application ---------------------------------
function Start-Application {
    param (
        [boolean]$gui
    )

    if (-not $gui) { $script:LOG_TO_SCREEN = $true }

    Test-Requirements -gui $gui | Out-Null
    $appContext = $script:APP_CONTEXT

    $params = @{
        appContext        = $appContext
        locations         = $locations
        searchPatterns    = $searchPatterns
        allowedMasks      = $allowedMasks
        excludedMasks     = $excludedMasks
        maxFileSize       = $maxFileSize
        encodings         = $encodings
        resultFilePath    = $resultFilePath
        keepResults       = $false
        searchResultHead  = $searchResultHead
        searchResultTrail = $searchResultTrail
        fileDateStart     = $fileDateStart
        fileDateEnd       = $fileDateEnd
    }

    if ($gui) {
        $form = Initialize-Form -baseParams $params 
        Set-TabConfigParams -params $params
        [System.Windows.Forms.Application]::Run($form)
    }
    else {
        Initialize-ConsoleSearch -params $params
    }

    Close-OutlookInstance $appContext
    Close-WordInstance $appContext
    Close-ExcelInstance $appContext
}

Start-Application -gui $gui