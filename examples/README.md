# PowerShell-YAML Examples

This directory contains examples demonstrating the features of PowerShell-YAML with typed class support.

## Quick Start

All examples require importing the module:

```powershell
Import-Module powershell-yaml
```

## Examples

### 1. typed-yaml-demo.ps1

**Comprehensive introduction to typed YAML serialization**

Demonstrates:
- Creating PowerShell classes that inherit from `YamlBase`
- Type-safe deserialization with `-As` parameter
- Nested objects (`AppConfig` → `DatabaseConfig`)
- Array handling (`AllowedOrigins`)
- Round-trip serialization
- Automatic property name conversion (PascalCase → hyphenated-case)

**Classes**: `classes/DemoClasses.ps1` (`DatabaseConfig`, `AppConfig`)

**Run**:
```powershell
pwsh -File examples/typed-yaml-demo.ps1
```

### 2. yamlkey-attribute.ps1

**YamlKey attribute for case-sensitive YAML keys**

Demonstrates:
- Using `[YamlKey("key-name")]` attribute
- Mapping case-sensitive YAML keys to different properties
- Solving PowerShell's case-insensitive property limitation

**Classes**: `classes/ServerConfig.ps1` (`ServerConfig`)

**Run**:
```powershell
pwsh -File examples/yamlkey-attribute.ps1
```

**Example**:
```powershell
class ServerConfig : YamlBase {
    [YamlKey("Host")]  # Maps to "Host" in YAML
    [string]$PrimaryHost

    [YamlKey("host")]  # Maps to "host" in YAML
    [string]$BackupHost
}
```

### 3. metadata-demo.ps1

**YAML metadata preservation (comments, tags, styles)**

Demonstrates:
- Automatic comment preservation from source YAML
- YAML tag preservation (`!!int`, `!!str`)
- Scalar style preservation (plain, single-quoted, double-quoted)
- Programmatic metadata manipulation via `Get/SetProperty*` methods
- Metadata survival through round-trip serialization

**Classes**: `classes/DemoClasses.ps1`

**Run**:
```powershell
pwsh -File examples/metadata-demo.ps1
```

**Example**:
```powershell
# Comments and tags are automatically preserved
$yaml = @"
# Application configuration
app-name: "MyApp"
port: !!int "8080"
"@

$config = $yaml | ConvertFrom-YamlTyped -As ([AppConfig])

# Access metadata
$config.GetPropertyComment('AppName')  # Returns: "Application configuration"
$config.GetPropertyTag('Port')         # Returns: "tag:yaml.org,2002:int"

# Add metadata
$config.SetPropertyComment('Environment', 'Deployment target')

# Metadata preserved when serializing
$newYaml = $config | ConvertTo-YamlTyped
```

### 4. duplicate-key-detection.ps1

**Duplicate key detection and prevention**

Demonstrates:
- PSCustomObject mode rejecting case-insensitive duplicate keys
- Typed mode validation requiring explicit `[YamlKey]` mappings
- Preventing silent data loss from key overwrites
- Handling multiple case variations (`test`, `Test`, `TEST`)
- Round-trip preservation of case-sensitive keys

**Classes**: `classes/DuplicateKeyClasses.ps1` (`ConfigWithoutMapping`, `ConfigWithMapping`, `ThreeVariations`)

**Run**:
```powershell
pwsh -File examples/duplicate-key-detection.ps1
```

**Example**:
```powershell
# This YAML has case-insensitive duplicate keys
$yaml = @"
test: hello
Test: world
"@

# PSCustomObject mode prevents data loss
$yaml | ConvertFrom-Yaml -As ([PSCustomObject])  # Throws error

# Typed mode without mappings also fails
class BadConfig : YamlBase {
    [string]$test
}
$yaml | ConvertFrom-Yaml -As ([BadConfig])  # Throws error

# Typed mode with explicit mappings succeeds
class GoodConfig : YamlBase {
    [YamlKey("test")]
    [string]$LowercaseValue

    [YamlKey("Test")]
    [string]$CapitalizedValue
}
$config = $yaml | ConvertFrom-Yaml -As ([GoodConfig])
# $config.LowercaseValue = "hello"
# $config.CapitalizedValue = "world"
```

### 5. advanced-features.ps1

**All features combined in a realistic scenario**

Demonstrates:
- `[YamlKey]` attribute for case-sensitive keys
- Custom YAML key mapping
- Nested `YamlBase` objects
- Arrays of `YamlBase` objects
- Automatic PascalCase → hyphenated-case conversion
- Full metadata preservation
- Complete round-trip with all features working together

**Classes**: `classes/AdvancedConfig.ps1` (`ServerEndpoint`, `AdvancedConfig`)

**Run**:
```powershell
pwsh -File examples/advanced-features.ps1
```

### 6. custom-converters.ps1

**Custom Type Converters - Extending YAML with Application-Specific Types**

Demonstrates:
- Creating custom converters by inheriting from `YamlConverter`
- Using `[YamlConverter("ConverterName")]` attribute to register converters
- Handling custom YAML tags (`!semver`, `!datetime`)
- Supporting multiple input formats (string and dictionary)
- Overriding standard YAML type handling
- Full round-trip with custom tag preservation
- Error handling for invalid input

**Classes**: `classes/CustomConverters.ps1` (`SemanticVersion`, `SemVerConverter`, `CustomDateTimeConverter`, `AppRelease`)

**Run**:
```powershell
pwsh -File examples/custom-converters.ps1
```

**Example**:
```powershell
# Define a custom type
class SemanticVersion {
    [int]$Major = 0
    [int]$Minor = 0
    [int]$Patch = 0
    [string]$PreRelease = ""
}

# Create a converter
class SemVerConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        return $targetType -eq [SemanticVersion]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        # Parse YAML data into SemanticVersion
        # ...
    }

    [object] ConvertToYaml([object]$value) {
        # Return hashtable with Value and Tag
        return @{
            Value = $value.ToString()
            Tag = '!semver'
        }
    }
}

# Use the converter
class AppRelease : YamlBase {
    [YamlConverter("SemVerConverter")]
    [SemanticVersion]$Version = $null
}

# Parse YAML with custom tag
$yaml = "version: !semver '2.1.5-beta3'"
$release = $yaml | ConvertFrom-Yaml -As ([AppRelease])
# $release.Version.Major = 2
# $release.Version.Minor = 1
# $release.Version.Patch = 5
# $release.Version.PreRelease = "beta3"
```

## Class Files

All class definitions are located in the `classes/` subdirectory and can be dot-sourced as needed.

### classes/DemoClasses.ps1

Simple configuration classes demonstrating:
- No need for manual `ToDictionary`/`FromDictionary` - handled automatically
- Nested `YamlBase` objects
- Arrays

```powershell
class DatabaseConfig : YamlBase {
    [string]$Host = 'localhost'
    [int]$Port = 5432
    # ...
}

class AppConfig : YamlBase {
    [string]$AppName = ''
    [DatabaseConfig]$Database = $null
    [string[]]$AllowedOrigins = @()
    # ...
}
```

### classes/ServerConfig.ps1

Demonstrates `[YamlKey]` attribute:

```powershell
class ServerConfig : YamlBase {
    [YamlKey("Host")]
    [string]$PrimaryHost = ""

    [YamlKey("host")]
    [string]$BackupHost = ""
}
```

### classes/DuplicateKeyClasses.ps1

Demonstrates duplicate key detection and prevention:

```powershell
# Without YamlKey - will fail with duplicate keys
class ConfigWithoutMapping : YamlBase {
    [string]$test = ""
}

# With explicit YamlKey - succeeds with duplicate keys
class ConfigWithMapping : YamlBase {
    [YamlKey("test")]
    [string]$LowercaseValue = ""

    [YamlKey("Test")]
    [string]$CapitalizedValue = ""
}

# Three case variations
class ThreeVariations : YamlBase {
    [YamlKey("test")]
    [string]$Lower = ""

    [YamlKey("Test")]
    [string]$Capital = ""

    [YamlKey("TEST")]
    [string]$Upper = ""
}
```

### classes/AdvancedConfig.ps1

Complex configuration with all features:

```powershell
class ServerEndpoint : YamlBase {
    [YamlKey("HTTP")]
    [string]$HttpUrl = ""

    [YamlKey("HTTPS")]
    [string]$HttpsUrl = ""
}

class AdvancedConfig : YamlBase {
    [ServerEndpoint]$PrimaryEndpoint = $null
    [ServerEndpoint[]]$BackupEndpoints = @()

    [YamlKey("max-retry-count")]
    [int]$MaxRetries = 3
}
```

### classes/CustomConverters.ps1

Custom type converters for application-specific types:

```powershell
# Custom type
class SemanticVersion {
    [int]$Major = 0
    [int]$Minor = 0
    [int]$Patch = 0
    [string]$PreRelease = ""

    [string] ToString() {
        $ver = "$($this.Major).$($this.Minor).$($this.Patch)"
        if ($this.PreRelease) { $ver += "-$($this.PreRelease)" }
        return $ver
    }
}

# Converter for SemanticVersion with !semver tag
class SemVerConverter : YamlConverter {
    [bool] CanHandle([string]$tag, [Type]$targetType) {
        return $targetType -eq [SemanticVersion]
    }

    [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
        # Supports both string ("1.2.3-beta") and dictionary formats
        # Returns SemanticVersion instance
    }

    [object] ConvertToYaml([object]$value) {
        return @{ Value = $value.ToString(); Tag = '!semver' }
    }
}

# Usage in a YamlBase class
class AppRelease : YamlBase {
    [YamlConverter("SemVerConverter")]
    [SemanticVersion]$Version = $null

    [YamlConverter("CustomDateTimeConverter")]
    [DateTime]$ReleaseDate = [DateTime]::MinValue
}
```

## Key Features

### 1. Default Implementations

No need to write `ToDictionary` or `FromDictionary` methods:

```powershell
# Before (manual implementation required):
class OldClass : YamlBase {
    [string]$Name

    [Dictionary[string, object]] ToDictionary() {
        # Manual implementation...
    }

    [void] FromDictionary([Dictionary[string, object]]$data) {
        # Manual implementation...
    }
}

# After (automatic):
class NewClass : YamlBase {
    [string]$Name  # That's it!
}
```

### 2. Automatic Property Name Conversion

PascalCase → hyphenated-case:

```powershell
class Config : YamlBase {
    [string]$AppName      # YAML key: app-name
    [string]$DatabaseHost # YAML key: database-host
    [int]$MaxConnections  # YAML key: max-connections
}
```

### 3. YamlKey Attribute

Override automatic conversion or handle case-sensitive keys:

```powershell
class Config : YamlBase {
    [YamlKey("API-Key")]     # Exact YAML key
    [string]$ApiKey

    [YamlKey("db_host")]     # Use underscores instead of hyphens
    [string]$DatabaseHost
}
```

### 4. Metadata Preservation

Comments, tags, and styles automatically preserved:

```powershell
$yaml = @"
# Important setting
port: !!int "8080"
name: 'MyApp'
"@

$config = $yaml | ConvertFrom-YamlTyped -As ([Config])

# Metadata is automatically captured
$config.GetPropertyComment('Port')      # "Important setting"
$config.GetPropertyTag('Port')          # "tag:yaml.org,2002:int"
$config.GetPropertyScalarStyle('Name')  # "SingleQuoted"

# Serialize back - metadata preserved!
$newYaml = $config | ConvertTo-YamlTyped
# Output includes comment, tag, and quotes
```

## Tips

1. **Always initialize properties with default values** to avoid nullability issues:
   ```powershell
   [string]$Name = ""      # Good
   [string]$Name           # May cause issues
   ```

2. **Use `YamlKey` for case-sensitive or special format keys**:
   ```powershell
   [YamlKey("UPPER")]
   [string]$UpperCase

   [YamlKey("snake_case")]
   [string]$SnakeCase
   ```

3. **Leverage automatic conversion** for standard keys:
   ```powershell
   [string]$AppName        # Auto-converts to app-name
   [int]$MaxConnections    # Auto-converts to max-connections
   ```

4. **Nest YamlBase objects freely** - they're handled automatically:
   ```powershell
   [DatabaseConfig]$Database = $null
   [ServerConfig[]]$Servers = @()
   ```

5. **Access metadata via `GetProperty*` methods**:
   ```powershell
   $obj.GetPropertyComment('PropName')
   $obj.GetPropertyTag('PropName')
   $obj.GetPropertyScalarStyle('PropName')
   ```

## Running All Examples

```powershell
# Run each example
pwsh -File examples/typed-yaml-demo.ps1
pwsh -File examples/yamlkey-attribute.ps1
pwsh -File examples/metadata-demo.ps1
pwsh -File examples/duplicate-key-detection.ps1
pwsh -File examples/advanced-features.ps1
pwsh -File examples/custom-converters.ps1
```
