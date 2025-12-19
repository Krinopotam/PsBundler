@{
    RootModule        = 'PsBundler.psm1'
    ModuleVersion     = '2.1.6'
    GUID              = '5bbc89a0-1efe-45ad-bd20-39e87f3c3373'
    Author            = 'Maxim Zaytsev'
    Copyright         = '(c) 2025 Maxim Zaytsev. All rights reserved.'
    Description       = 'A PowerShell bundler that merges multiple script files into a single bundle file.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-PSBundler')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # All modules list of the module
    # ModuleList = @()

    # All files list of the module
    # FileList = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('powershell', 'bundler', 'builder', 'compiler', 'module', 'scripts', 'automation', 'devtools', 'build', 'packaging', 'merge', 'tooling')
            LicenseUri = 'https://github.com/Krinopotam/PsBundler/blob/master/LICENSE'
            ProjectUri = 'https://github.com/Krinopotam/PsBundler'
            IconUri = 'https://raw.githubusercontent.com/Krinopotam/PsBundler/main/icons/psbundler_128.png'
            # ReleaseNotes = ''
        }

    } 

    # Help Info URI of this module
    # HelpInfoURI = ''
}
