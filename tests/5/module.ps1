using module .\hoisted-only.psm1

class AddTypePlacementTestClass {
    [object]CreateHoistedType() {
        return [PsBundler.Tests.HoistedType]::new()
    }
}

$dynamicTypeSource = @'
namespace PsBundler.Tests {
    public class DynamicType {}
}
'@
Add-Type -TypeDefinition $dynamicTypeSource

Add-Type -TypeDefinition 'namespace PsBundler.Tests { public class PipelineType {} }' | Out-Null

if (-not ("PsBundler.Tests.ShouldLoad" -as [type])) {
    Add-Type -TypeDefinition @'
namespace PsBundler.Tests {
    public class ShouldLoad {}
}
'@
}

if ($false) {
    Add-Type -TypeDefinition @'
namespace PsBundler.Tests {
    public class ShouldStayUnloaded {}
}
'@
}
