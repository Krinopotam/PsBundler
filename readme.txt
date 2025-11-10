It is recommended to perform imports always use . "$PSScriptRoot/myfile.ps1" notation
$PSScriptRoot always returns the path to the directory of the current file where the import is specified.

When using a relative path for import, such as "./module.ps1", it is resolved relative to the PowerShell working directory (similar to $PWD).
For example, if a project PROJECT is opened in an IDE and the source files are located in the "project/src" folder, 
then running the "project/src/main.ps1" script via the IDE will resolve the path relative to "project", not "project/src".
However, if the script is run manually from the "project/src" folder via PowerShell, the path will be resolved relative to "project/src", which is not consistent.
