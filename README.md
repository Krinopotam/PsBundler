# PsBundler

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey?logo=powershell)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)
![Type](https://img.shields.io/badge/Type-Bundler-orange)

**PsBundler** is a PowerShell module for **bundling PowerShell projects into a single script file**.  
It analyzes script dependencies, imported modules, functions, and classes, and produces a standalone `.ps1` bundle suitable for distribution or deployment.

The module relies on **PowerShell AST analysis**, ensuring correct dependency resolution and safe composition even for complex projects.

---

## 🧩 Features

- 📦 Bundle PowerShell projects into a **single file**
- 🧠 Dependency resolution via AST analysis
- 🧩 Correct handling of `using`, `Import-Module`, dot-sourcing (`.`), call operator (`&`), functions, and classes
- 🔁 Detection and reporting of **cyclic imports**
- ✂️ Comment stripping
- 🧾 Entry-file header comment preservation
- 🧬 Deferred class compilation
- 🔐 Base64 or here-string class embedding
- 🛡️ Optional output obfuscation (experimental)

---

## 📦 Installation

You can install **PsBundler** from the **PowerShell Gallery** or directly from **GitHub**.

### 🏗️ Option 1 — From PowerShell Gallery

```powershell
Install-Module PsBundler -Scope CurrentUser -Force
```

Import the module:

```powershell
Import-Module PsBundler
```

### 💾 Option 2 — From GitHub

1. Clone or download the repository:

   ```powershell
   git clone https://github.com/Krinopotam/PsBundler.git
   ```

2. Import the module manually:

   ```powershell
   Import-Module .\PsBundler\src\PsBundler.psd1
   ```

3. (Optional) Copy the module to a standard PowerShell module path:

   ```powershell
   $env:USERPROFILE\Documents\WindowsPowerShell\Modules\PsBundler
   ```

### 📜 Option 3 — Standalone bundled script

PsBundler is also distributed as a **self-contained bundled script**, generated using PsBundler itself.

Prebuilt standalone bundles are published on the
[latest GitHub release](https://github.com/Krinopotam/PsBundler/releases/latest).

This standalone script contains the full PsBundler implementation and does **not require module installation or import**.

---

## 🚀 Usage (Module)

### Basic workflow

1. Create a configuration file named **`psbundler.config.json`**.  
   At minimum, the configuration must define `projectRoot`, `outDir`, and `entryPoints`.
2. Ensure the configuration file is located in the directory from which PsBundler is executed  
   (or specify its path explicitly using `-configPath`).
3. Run PsBundler from the project root using:

```powershell
Invoke-PsBundler
```

As a result, PsBundler will generate a **separate bundled PowerShell script for each configured entry point**.  
The output file name is taken from the **value of the `entryPoints` map**, and each bundle contains:

- the corresponding entry script
- all resolved dependencies
- functions, modules, and classes in the correct order

---

## 🚀 Usage (Standalone Script)

PsBundler can also be used as a **standalone bundled script**.  
This mode does not require module installation or import.

### Recommended setup

It is recommended to place:

- the standalone script (`psbundler-X.X.X.ps1`)
- the configuration file (`psbundler.config.json`)

together in the **root directory of your project**.

### Execution

You can run the script from the PowerShell command line:

```powershell
./psbundler-X.X.X.ps1
```

or explicitly specify the configuration path:

```powershell
./psbundler-X.X.X.ps1 -configPath path/to/psbundler.config.json
```

On Windows, the standalone script can also be executed via the **context menu**
by right-clicking the file `psbundler-X.X.X.ps1` and selecting “**Run with PowerShell**”.

The standalone script supports the same configuration file format and command-line parameters as the module version, including `-configPath`.

In addition to executing the standalone script as a file, PsBundler can also be used by **copying the entire contents of the bundled script and pasting it directly into a PowerShell console**.

This option is useful when:

- installing modules is not possible or undesirable
- a fully portable, single-file solution is required
- PsBundler needs to be used in restricted or isolated environments

## ⚙️ Configuration

PsBundler is configured via the **`psbundler.config.json`** file.  
If no configuration path is explicitly provided, PsBundler looks for this file in the **current working directory** (the directory from which PsBundler is executed).  
A custom configuration file path can be specified explicitly using the **`-configPath`** parameter.

### Example configuration

```json
{
  "projectRoot": ".\\",
  "outDir": "build",
  "entryPoints": {
    "entry.ps1": "myBundle.ps1"
  },
  "stripComments": true,
  "keepHeaderComments": true,
  "deferClassesCompilation": true,
  "embedClassesAsBase64": false
}
```

### Configuration options

| Option | Type | Description |
| ------ | ---- | ----------- |
| `projectRoot` | string | Project root directory (relative to the **configuration file path**) |
| `outDir` | string | Output directory (relative to `projectRoot`) |
| `entryPoints` | object | Entry point map (`sourceFile → outputFile`, relative to `projectRoot`) |
| `stripComments` | bool | Removes comments from the bundled output |
| `keepHeaderComments` | bool | Preserves header comment blocks from entry files |
| `obfuscate` | bool / string | Obfuscation mode: `true` (equivalent to `"Hard"`), `"Natural"`, or `"Hard"` |
| `deferClassesCompilation` | bool | Defers class compilation using `Invoke-Expression` |
| `embedClassesAsBase64` | bool | Embeds deferred classes as Base64 instead of here-strings |

---

### Option details

#### `projectRoot`

Defines the **project root directory**, relative to the **configuration file path**.  
All source paths, including entry points and dependencies, are resolved relative to this directory.

---

#### `outDir`

Specifies the output directory for generated bundles.  
The path is resolved **relative to `projectRoot`**.  
If the directory does not exist, it will be created automatically.

---

#### `entryPoints`

Defines the set of entry scripts to bundle.

Each entry point produces **its own bundled output file**, allowing multiple independent entry scripts to be bundled within a single project.

The map key represents the **source script path** (relative to `projectRoot`), while the value defines the **output file name** (relative to `projectRoot`). If the entry script contains a version specified in its header comments (for example: `# Version: 1.2.3`), this version will be **automatically appended to the bundle file name**.

---

#### `stripComments`

Controls whether comments are removed from the bundled output.

When enabled, all comments are stripped from the generated bundle, reducing file size and improving readability or obfuscation effectiveness.  
Header comments may still be preserved if `keepHeaderComments` is enabled.

---

#### `keepHeaderComments`

Controls whether **header comment blocks** from entry files are preserved in the bundled output.  
This is typically used to keep metadata comments such as author information, descriptions, or license headers (for example: `# Author`, `# Description`, etc.) at the top of each generated bundle.

---

#### `obfuscate`

Enables **experimental code obfuscation**.

- Only **functions and variables** are obfuscated
- **Classes and class methods are ignored** and left unchanged

Supported modes:

- `"Natural"` — obfuscated names resemble natural but meaningless identifiers
- `"Hard"` — obfuscated names are highly unreadable and intentionally complex

**This feature is experimental and intended primarily for lightweight code protection rather than strong security guarantees.**

---

#### `deferClassesCompilation`

Controls how PowerShell classes are handled during bundling.

PowerShell classes perform **type validation at parse time**, meaning that all referenced types must be known and available **before the script is executed**.  
At the same time, `Add-Type` and even `using assembly` load external assemblies **at runtime**, not during parsing.

This mismatch can cause situations where:

- class definitions reference types that are not yet loaded
- the bundled script fails to parse, even though the original project works correctly

When this option is enabled:

- Class definitions are stored as **plain text variables**
- They are compiled later at runtime using `Invoke-Expression`, after all required assemblies have been loaded

This mode:

- Significantly improves compatibility with projects using classes and external assemblies
- Has negligible performance impact
- Removes the ability to debug class definitions in the final bundled script

Recommended for projects that use PowerShell classes together with `Add-Type` or `using assembly`.

---

#### `embedClassesAsBase64`

This option is only relevant when `deferClassesCompilation` is enabled.

- When set to `false`, class source code is embedded as **here-strings**
  - Easier for humans to read
  - May cause issues if class code itself contains here-strings (since here-strings cannot be escaped)

- When set to `true`, class source code is embedded as **Base64**
  - Safest and most compatible mode
  - Recommended if classes contain here-strings

If your project’s classes do not use here-strings, it is safe to leave this option set to `false`.

---

## 🧩 Requirements

- **PowerShell:** 5.1 or higher  
- **Platforms:** Windows / Linux / macOS  
- **External dependencies:** none

---

## ⚙️ Technical Details

Internally, **PsBundler** uses:

- `System.Management.Automation.Language.Parser`
- static AST analysis
- custom dependency resolution logic

This approach allows PsBundler to:

- avoid duplicate declarations
- preserve correct declaration order
- safely bundle complex multi-file PowerShell projects

---

## ⚠️ Limitations

- **Cyclic imports are not supported**.  
  If a circular dependency between scripts or modules is detected, PsBundler will report detailed information about the cycle, but bundle generation will fail.

  Circular import resolution is intentionally not performed, as it can lead to ambiguous execution order and unpredictable runtime behavior in bundled scripts.

---

## 📄 License

This project is licensed under the **Apache License 2.0**.  
See the LICENSE file for details.
