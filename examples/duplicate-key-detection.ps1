#!/usr/bin/env pwsh
# Example: Duplicate Key Detection - Preventing Data Loss

Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

# Load class definitions
. "$PSScriptRoot/classes/DuplicateKeyClasses.ps1"

Write-Host "=== Duplicate Key Detection Demo ===" -ForegroundColor Cyan
Write-Host ""

# Example 1: PSCustomObject mode rejects duplicate keys
Write-Host "Example 1: PSCustomObject mode prevents data loss" -ForegroundColor Yellow
Write-Host "------------------------------------------------"

$yaml = @"
test: hello
Test: world
"@

Write-Host "Input YAML with case-insensitive duplicate keys:"
Write-Host $yaml
Write-Host ""

try {
    $obj = $yaml | ConvertFrom-Yaml -As ([PSCustomObject])
    Write-Host "ERROR: Should have thrown an error!" -ForegroundColor Red
} catch {
    Write-Host "✓ Correctly rejected duplicate keys:" -ForegroundColor Green
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host ""

# Example 2: Typed mode without explicit mappings fails
Write-Host "Example 2: Typed mode without YamlKey attributes" -ForegroundColor Yellow
Write-Host "------------------------------------------------"

Write-Host "Class definition:"
Write-Host "  class ConfigWithoutMapping : YamlBase {"
Write-Host "      [string]`$test = `"`""
Write-Host "  }"
Write-Host ""

try {
    $obj = $yaml | ConvertFrom-Yaml -As ([ConfigWithoutMapping])
    Write-Host "ERROR: Should have thrown an error!" -ForegroundColor Red
} catch {
    Write-Host "✓ Correctly rejected unmapped duplicate keys:" -ForegroundColor Green
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host ""

# Example 3: Typed mode WITH explicit mappings succeeds
Write-Host "Example 3: Typed mode with explicit YamlKey mappings" -ForegroundColor Yellow
Write-Host "------------------------------------------------"

Write-Host "Class definition:"
Write-Host "  class ConfigWithMapping : YamlBase {"
Write-Host "      [YamlKey(`"test`")]"
Write-Host "      [string]`$LowercaseValue = `"`""
Write-Host ""
Write-Host "      [YamlKey(`"Test`")]"
Write-Host "      [string]`$CapitalizedValue = `"`""
Write-Host "  }"
Write-Host ""

try {
    $obj = $yaml | ConvertFrom-Yaml -As ([ConfigWithMapping])
    Write-Host "✓ Successfully parsed with explicit mappings:" -ForegroundColor Green
    Write-Host "  LowercaseValue (from 'test'): $($obj.LowercaseValue)"
    Write-Host "  CapitalizedValue (from 'Test'): $($obj.CapitalizedValue)"
} catch {
    Write-Host "ERROR: Should have succeeded!" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host ""

# Example 4: Round-trip preservation
Write-Host "Example 4: Round-trip with case-sensitive keys" -ForegroundColor Yellow
Write-Host "------------------------------------------------"

$obj.LowercaseValue = "modified lowercase"
$obj.CapitalizedValue = "MODIFIED UPPERCASE"

$newYaml = $obj | ConvertTo-Yaml

Write-Host "Serialized YAML (case preserved):"
Write-Host $newYaml
Write-Host ""

# Deserialize again to verify
$obj2 = $newYaml | ConvertFrom-Yaml -As ([ConfigWithMapping])
Write-Host "✓ Round-trip successful:" -ForegroundColor Green
Write-Host "  LowercaseValue: $($obj2.LowercaseValue)"
Write-Host "  CapitalizedValue: $($obj2.CapitalizedValue)"

Write-Host ""
Write-Host ""

# Example 5: Multiple case variations
Write-Host "Example 5: Three case variations" -ForegroundColor Yellow
Write-Host "------------------------------------------------"

$yaml3 = @"
test: lowercase
Test: capitalized
TEST: uppercase
"@

Write-Host "Input YAML:"
Write-Host $yaml3
Write-Host ""

$obj3 = $yaml3 | ConvertFrom-Yaml -As ([ThreeVariations])

Write-Host "✓ Successfully parsed three case variations:" -ForegroundColor Green
Write-Host "  Lower (from 'test'): $($obj3.Lower)"
Write-Host "  Capital (from 'Test'): $($obj3.Capital)"
Write-Host "  Upper (from 'TEST'): $($obj3.Upper)"
