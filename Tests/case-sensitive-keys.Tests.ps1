#!/usr/bin/env pwsh
# Case-Sensitive Keys Tests: Demonstrates YamlKey attribute for mapping YAML keys to properties

BeforeAll {
    # Import the main module (now includes typed cmdlets)
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Load test classes
    . "$PSScriptRoot/CaseSensitiveKeys.ps1"
}

Describe "YamlKey Attribute: Case-Sensitive YAML Keys" {
    It "Should map case-sensitive YAML keys to different properties" {
        # YAML with keys that differ only by case
        $yaml = @"
Test: I am uppercase
test: 42
"@

        # Deserialize
        $obj = $yaml | ConvertFrom-Yaml -As ([CaseSensitiveTest])

        # Verify values were mapped to correct properties
        $obj.CapitalizedTest | Should -Be "I am uppercase"
        $obj.LowercaseTest | Should -Be 42
        $obj.CapitalizedTest | Should -BeOfType [string]
        $obj.LowercaseTest | Should -BeOfType [int]
    }

    It "Should serialize with correct case-sensitive keys" {
        # Create object
        $obj = [CaseSensitiveTest]::new()
        $obj.CapitalizedTest = "Hello"
        $obj.LowercaseTest = 100

        # Serialize
        $yaml = $obj | ConvertTo-Yaml

        # Verify keys have correct case
        $yaml | Should -Match "Test: Hello"
        $yaml | Should -Match "test: 100"
    }

    It "Should round-trip case-sensitive keys" {
        $yaml = @"
Test: Original uppercase
test: 999
"@

        # Deserialize
        $obj = $yaml | ConvertFrom-Yaml -As ([CaseSensitiveTest])

        # Modify values
        $obj.CapitalizedTest = "Modified uppercase"
        $obj.LowercaseTest = 888

        # Serialize back
        $newYaml = $obj | ConvertTo-Yaml

        # Verify case is preserved
        $newYaml | Should -Match "Test: Modified uppercase"
        $newYaml | Should -Match "test: 888"

        # Deserialize again to verify
        $obj2 = $newYaml | ConvertFrom-Yaml -As ([CaseSensitiveTest])
        $obj2.CapitalizedTest | Should -Be "Modified uppercase"
        $obj2.LowercaseTest | Should -Be 888
    }

    It "Should work with mixed attribute and auto-conversion" {
        $yaml = @"
custom-key: Custom value
auto-converted-key: 200
"@

        $obj = $yaml | ConvertFrom-Yaml -As ([MixedKeysTest])

        # Attribute-mapped property
        $obj.CustomProperty | Should -Be "Custom value"
        # Auto-converted property (AutoConvertedKey -> auto-converted-key)
        $obj.AutoConvertedKey | Should -Be 200
    }

    It "Should serialize mixed keys correctly" {
        $obj = [MixedKeysTest]::new()
        $obj.CustomProperty = "Custom"
        $obj.AutoConvertedKey = 300

        $yaml = $obj | ConvertTo-Yaml

        # Verify both key types
        $yaml | Should -Match "custom-key: Custom"
        $yaml | Should -Match "auto-converted-key: 300"
    }

    It "Should preserve metadata for attribute-mapped properties" {
        $yaml = @"
# This is a custom key comment
custom-key: Value with comment
auto-converted-key: 150
"@

        $obj = $yaml | ConvertFrom-Yaml -As ([MixedKeysTest])

        # Verify comment is associated with the correct property
        $obj.GetPropertyComment('CustomProperty') | Should -Match "custom key comment"

        # Serialize back
        $newYaml = $obj | ConvertTo-Yaml

        # Comment should be preserved
        $newYaml | Should -Match "# This is a custom key comment"
        $newYaml | Should -Match "custom-key: Value with comment"
    }
}

Describe "Duplicate Key Detection" {
    It "Should error on duplicate keys in PSCustomObject mode" {
        $yaml = @"
test: hello
Test: world
"@

        # This should throw because PSCustomObject mode doesn't allow case-insensitive duplicates
        { $yaml | ConvertFrom-Yaml -As ([PSCustomObject]) } | Should -Throw "*Duplicate key*"
    }

    It "Should error on duplicate keys without explicit YamlKey mapping in typed mode" {
        $yaml = @"
test: hello
Test: world
"@

        # This should throw because the type doesn't have YamlKey attributes for both variations
        { $yaml | ConvertFrom-Yaml -As ([IWillFailDueToDuplicateKey]) } | Should -Throw "*case-insensitive duplicate keys*"
    }

    It "Should succeed with duplicate keys when all are explicitly mapped" {
        $yaml = @"
test: hello
Test: world
"@

        # This should work because both keys are explicitly mapped with YamlKey attributes
        $obj = $yaml | ConvertFrom-Yaml -As ([IWillSucceedBecauseIHaveAMappedKey])

        # Verify both values were mapped correctly
        $obj.test | Should -Be "hello"
        $obj.alsoTestButUppercase | Should -Be "world"
    }

    It "Should round-trip duplicate keys with explicit mappings" {
        $yaml = @"
test: lowercase value
Test: uppercase value
"@

        # Deserialize
        $obj = $yaml | ConvertFrom-Yaml -As ([IWillSucceedBecauseIHaveAMappedKey])

        # Modify values
        $obj.test = "modified lowercase"
        $obj.alsoTestButUppercase = "modified uppercase"

        # Serialize back
        $newYaml = $obj | ConvertTo-Yaml

        # Verify both keys are preserved with correct case
        $newYaml | Should -Match "test: modified lowercase"
        $newYaml | Should -Match "Test: modified uppercase"

        # Deserialize again to verify
        $obj2 = $newYaml | ConvertFrom-Yaml -As ([IWillSucceedBecauseIHaveAMappedKey])
        $obj2.test | Should -Be "modified lowercase"
        $obj2.alsoTestButUppercase | Should -Be "modified uppercase"
    }

    It "Should error with helpful message indicating which keys are unmapped" {
        $yaml = @"
test: value1
Test: value2
TEST: value3
"@

        # This should throw with a message indicating which keys lack explicit mappings
        $errorMessage = ""
        try {
            $yaml | ConvertFrom-Yaml -As ([IWillFailDueToDuplicateKey])
        } catch {
            $errorMessage = $_.Exception.Message
        }

        # Error should mention the duplicate keys
        $errorMessage | Should -Match "test"
        $errorMessage | Should -Match "Test"
        # Error should mention the solution
        $errorMessage | Should -Match "YamlKey"
    }
}
