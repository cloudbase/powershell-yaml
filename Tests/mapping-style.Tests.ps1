#!/usr/bin/env pwsh
# Copyright 2016-2026 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# Tests for mapping style preservation (Flow vs Block)

BeforeAll {
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force
    . "$PSScriptRoot/MappingStyleClasses.ps1"
}

Describe "Mapping Style Preservation" {
    Context "Flow style mappings" {
        It "Should preserve flow style for nested objects" {
            $yaml = @"
name: "TechCorp"
ceo: {name: "swift-narwhal", age: 45, address: {street: "123 Main St", city: "Seattle", zip: "98101"}}
employees: []
"@

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify data was parsed correctly
            $company.Name | Should -Be "TechCorp"
            $company.Ceo.Name | Should -Be "swift-narwhal"
            $company.Ceo.Age | Should -Be 45
            $company.Ceo.Address.Street | Should -Be "123 Main St"
            $company.Ceo.Address.City | Should -Be "Seattle"
            $company.Ceo.Address.Zip | Should -Be "98101"

            # Verify flow style was preserved
            $company.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"
            $company.Ceo.GetPropertyMappingStyle('Address') | Should -Be "Flow"

            # Round-trip and verify flow style is maintained
            $roundTripped = $company | ConvertTo-Yaml

            # Flow style should produce inline format
            $roundTripped | Should -Match "ceo:\s*\{.*name:.*swift-narwhal.*\}"
            $roundTripped | Should -Match "address:.*\{.*street:.*123 Main St.*\}"
        }

        It "Should preserve block style for nested objects" {
            $yaml = @"
name: "StartupInc"
ceo:
  name: "eager-dolphin"
  age: 35
  address:
    street: "456 Tech Ave"
    city: "San Francisco"
    zip: "94105"
employees: []
"@

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify data was parsed correctly
            $company.Ceo.Name | Should -Be "eager-dolphin"
            $company.Ceo.Address.City | Should -Be "San Francisco"

            # Verify block style was preserved (or not set, which defaults to block)
            $ceoStyle = $company.GetPropertyMappingStyle('Ceo')
            $ceoStyle | Should -BeIn @($null, "Block")

            # Round-trip and verify block style is maintained
            $roundTripped = $company | ConvertTo-Yaml

            # Block style should produce multi-line format
            $roundTripped | Should -Match "ceo:\s*\n\s+name:"
            $roundTripped | Should -Match "address:\s*\n\s+street:"
        }

        It "Should handle mixed flow and block styles" {
            $yaml = @"
name: "MixedCorp"
ceo:
  name: "brave-penguin"
  age: 50
  address: {street: "789 Business Blvd", city: "Austin", zip: "78701"}
employees: []
"@

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # CEO is block style, but address is flow style
            $company.GetPropertyMappingStyle('Ceo') | Should -BeIn @($null, "Block")
            $company.Ceo.GetPropertyMappingStyle('Address') | Should -Be "Flow"

            # Round-trip
            $roundTripped = $company | ConvertTo-Yaml

            # CEO should be block
            $roundTripped | Should -Match "ceo:\s*\n\s+name:"
            # Address should be flow
            $roundTripped | Should -Match "address:.*\{.*street:.*789 Business Blvd.*\}"
        }

        It "Should allow programmatic setting of mapping style" {
            $company = [Company]::new()
            $company.Name = "StyleTest"

            $ceo = [Person]::new()
            $ceo.Name = "clever-otter"
            $ceo.Age = 40

            $address = [Address]::new()
            $address.Street = "321 Park Ave"
            $address.City = "New York"
            $address.Zip = "10001"

            $ceo.Address = $address
            $company.Ceo = $ceo

            # Set flow style programmatically
            $company.SetPropertyMappingStyle('Ceo', 'Flow')
            $ceo.SetPropertyMappingStyle('Address', 'Flow')

            # Serialize
            $yaml = $company | ConvertTo-Yaml

            # Should use flow style
            $yaml | Should -Match "ceo:.*\{.*name:.*clever-otter.*\}"
            $yaml | Should -Match "address:.*\{.*street:.*321 Park Ave.*\}"
        }

        It "Should default to block style when no metadata" {
            $company = [Company]::new()
            $company.Name = "DefaultStyleCorp"

            $ceo = [Person]::new()
            $ceo.Name = "calm-falcon"
            $ceo.Age = 42

            $company.Ceo = $ceo

            # Don't set any style - should default to block
            $yaml = $company | ConvertTo-Yaml

            # Should use block style (multi-line)
            $yaml | Should -Match "ceo:\s*\n\s+name:"
        }
    }

    Context "Flow style with arrays" {
        It "Should handle flow style objects in arrays" {
            $yaml = @"
name: "ArrayTest"
ceo: {name: "bright-tiger", age: 55, address: null}
employees:
  - {name: "happy-panda", age: 30, address: null}
  - {name: "wise-raven", age: 28, address: null}
"@

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify CEO is flow style
            $company.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"

            # Verify employees array was parsed
            $company.Employees.Count | Should -Be 2
            $company.Employees[0].Name | Should -Be "happy-panda"
            $company.Employees[1].Name | Should -Be "wise-raven"

            # Round-trip
            $roundTripped = $company | ConvertTo-Yaml

            # CEO should remain flow style
            $roundTripped | Should -Match "ceo:.*\{.*name:.*bright-tiger.*\}"
        }
    }

    Context "Entire document in flow style" {
        It "Should preserve flow style for entire deeply nested structure" {
            $yaml = @"
{name: "FlowCorp", ceo: {name: "gentle-whale", age: 52, address: {street: "999 Flow St", city: "Portland", zip: "97201"}}, employees: [{name: "quick-fox", age: 33, address: {street: "111 Dev Ave", city: "Portland", zip: "97202"}}, {name: "noble-hawk", age: 29, address: {street: "222 Code Ln", city: "Portland", zip: "97203"}}]}
"@

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify all data was parsed correctly
            $company.Name | Should -Be "FlowCorp"
            $company.Ceo.Name | Should -Be "gentle-whale"
            $company.Ceo.Age | Should -Be 52
            $company.Ceo.Address.Street | Should -Be "999 Flow St"
            $company.Ceo.Address.City | Should -Be "Portland"
            $company.Ceo.Address.Zip | Should -Be "97201"

            $company.Employees.Count | Should -Be 2
            $company.Employees[0].Name | Should -Be "quick-fox"
            $company.Employees[0].Age | Should -Be 33
            $company.Employees[0].Address.Street | Should -Be "111 Dev Ave"
            $company.Employees[1].Name | Should -Be "noble-hawk"
            $company.Employees[1].Age | Should -Be 29
            $company.Employees[1].Address.City | Should -Be "Portland"

            # Verify document-level flow style
            $company.GetDocumentMappingStyle() | Should -Be "Flow"

            # Verify flow style was captured for all nested objects
            $company.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"
            $company.Ceo.GetPropertyMappingStyle('Address') | Should -Be "Flow"

            # Round-trip and verify flow style is maintained throughout
            $roundTripped = $company | ConvertTo-Yaml

            # CEO and nested address should be flow style
            $roundTripped | Should -Match "ceo:\s*\{.*name:.*gentle-whale.*\}"
            $roundTripped | Should -Match "address:\s*\{.*street:.*999 Flow St.*\}"

            # Verify the structure is preserved
            $roundTripped | Should -Match "name:.*FlowCorp"
            $roundTripped | Should -Match "city:.*Portland"
        }

        It "Should round-trip single-line flow style document" {
            # Single-line YAML document (all in flow style)
            $yaml = "{name: CompactCorp, ceo: {name: silent-spider, age: 47, address: {street: 777 Compact Rd, city: Austin, zip: '78704'}}, employees: []}"

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify parsing
            $company.Name | Should -Be "CompactCorp"
            $company.Ceo.Name | Should -Be "silent-spider"
            $company.Ceo.Address.Street | Should -Be "777 Compact Rd"
            $company.Ceo.Address.Zip | Should -Be "78704"

            # Verify root document has flow style (this is what makes it truly single-line)
            $company.GetDocumentMappingStyle() | Should -Be "Flow"

            # Verify flow style preserved for nested objects
            $company.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"
            $company.Ceo.GetPropertyMappingStyle('Address') | Should -Be "Flow"

            # Round-trip
            $roundTripped = $company | ConvertTo-Yaml

            # The round-tripped output should exactly match the original (minus trailing whitespace)
            $roundTripped.Trim() | Should -Be $yaml.Trim() -Because "True round-trip should produce identical output"

            # Verify the output is actually a single line (no newlines except at the end)
            $lines = $roundTripped -split "`n"
            $nonEmptyLines = $lines | Where-Object { $_ -ne "" }
            $nonEmptyLines.Count | Should -Be 1 -Because "Flow style document should be a single line"

            # Verify the round-tripped output matches flow style format
            $roundTripped | Should -Match "^\{.*name:.*CompactCorp.*ceo:.*\{.*name:.*silent-spider.*\}.*\}"

            # Parse the round-tripped YAML back to verify exact round-trip
            $company2 = $roundTripped | ConvertFrom-Yaml -As ([Company])

            # Verify data matches exactly
            $company2.Name | Should -Be $company.Name
            $company2.Ceo.Name | Should -Be $company.Ceo.Name
            $company2.Ceo.Age | Should -Be $company.Ceo.Age
            $company2.Ceo.Address.Street | Should -Be $company.Ceo.Address.Street
            $company2.Ceo.Address.City | Should -Be $company.Ceo.Address.City
            $company2.Ceo.Address.Zip | Should -Be $company.Ceo.Address.Zip
            $company2.Employees.Count | Should -Be $company.Employees.Count

            # Verify flow style is maintained in round-trip (including root document)
            $company2.GetDocumentMappingStyle() | Should -Be "Flow"
            $company2.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"
            $company2.Ceo.GetPropertyMappingStyle('Address') | Should -Be "Flow"

            # Second round-trip should produce identical output (true round-trip stability)
            $roundTripped2 = $company2 | ConvertTo-Yaml
            $roundTripped2 | Should -Be $roundTripped
        }

        It "Should preserve flow style with null values" {
            $yaml = "{name: 'NullFlowCorp', ceo: {name: 'proud-eagle', age: 41, address: null}, employees: []}"

            $company = $yaml | ConvertFrom-Yaml -As ([Company])

            # Verify parsing with null
            $company.Name | Should -Be "NullFlowCorp"
            $company.Ceo.Name | Should -Be "proud-eagle"
            $company.Ceo.Address | Should -BeNullOrEmpty

            # Verify document-level flow style preserved
            $company.GetDocumentMappingStyle() | Should -Be "Flow"

            # Verify nested flow style preserved
            $company.GetPropertyMappingStyle('Ceo') | Should -Be "Flow"

            # Round-trip
            $roundTripped = $company | ConvertTo-Yaml

            # CEO should remain flow style even with null address
            $roundTripped | Should -Match "ceo:\s*\{.*name:.*proud-eagle.*\}"
        }
    }
}
