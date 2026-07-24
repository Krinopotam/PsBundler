Add-Type -TypeDefinition @'
namespace PsBundler.Tests {
    public class HoistedType {}
}
'@

# Identical commands must remain distinct executions in the generated preamble.
Add-Type -AssemblyName System.Xml
Add-Type -AssemblyName System.Xml
