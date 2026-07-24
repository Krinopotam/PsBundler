class AddTypePlacementTestClass {
}

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
