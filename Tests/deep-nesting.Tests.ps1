#!/usr/bin/env pwsh
# Deep Nesting Tests: Demonstrates round-tripping with deeply nested YamlBase objects

BeforeAll {
    # Import the main module (now includes typed cmdlets)
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force

    # Load test classes
    . "$PSScriptRoot/DeepNestingClasses.ps1"
}

Describe "Deep Nesting: Round-trip with Complex Object Hierarchies" {
    It "Should round-trip deeply nested objects with tags and comments" {
        $yaml = @"
# Document describing a family
title: The Smith Family
family:
  # Mother's information
  mom:
    name: Jane Smith
    age: !!int 45
  # Father's information
  dad:
    name: John Smith
    age: !!int 47
  # Children in the family
  children:
    - name: Alice Smith
      age: !!int 18
    - name: Bob Smith
      age: !!int 15
"@

        # Deserialize
        $obj = $yaml | ConvertFrom-Yaml -As ([MyClass])

        # Verify structure
        $obj.Title | Should -Be "The Smith Family"
        $obj.Family | Should -Not -BeNullOrEmpty
        $obj.Family.Mom.Name | Should -Be "Jane Smith"
        $obj.Family.Mom.Age | Should -Be 45
        $obj.Family.Dad.Name | Should -Be "John Smith"
        $obj.Family.Dad.Age | Should -Be 47
        $obj.Family.Children.Count | Should -Be 2
        $obj.Family.Children[0].Name | Should -Be "Alice Smith"
        $obj.Family.Children[0].Age | Should -Be 18

        # Verify comments were preserved
        $obj.GetPropertyComment('Title') | Should -Match "Document describing a family"
        $obj.Family.GetPropertyComment('Mom') | Should -Match "Mother's information"
        $obj.Family.GetPropertyComment('Dad') | Should -Match "Father's information"
        $obj.Family.GetPropertyComment('Children') | Should -Match "Children in the family"

        # Verify tags were preserved
        $obj.Family.Mom.GetPropertyTag('Age') | Should -Be "tag:yaml.org,2002:int"
        $obj.Family.Dad.GetPropertyTag('Age') | Should -Be "tag:yaml.org,2002:int"

        # Serialize back
        $newYaml = $obj | ConvertTo-Yaml

        # Verify tags are in output
        $newYaml | Should -Match "age: !!int 45"
        $newYaml | Should -Match "age: !!int 47"
        $newYaml | Should -Match "age: !!int 18"
        $newYaml | Should -Match "age: !!int 15"

        # Verify comments are in output
        $newYaml | Should -Match "# Document describing a family"
        $newYaml | Should -Match "# Mother's information"
        $newYaml | Should -Match "# Father's information"
        $newYaml | Should -Match "# Children in the family"

        # Verify structure is preserved
        $newYaml | Should -Match "title: The Smith Family"
        $newYaml | Should -Match "name: Jane Smith"
        $newYaml | Should -Match "name: John Smith"
        $newYaml | Should -Match "name: Alice Smith"
        $newYaml | Should -Match "name: Bob Smith"
    }

    It "Should handle partial null values with -OmitNull" {
        $yaml = @"
title: The Johnson Family
family:
  mom:
    name: Mary Johnson
    age: 42
  dad: null
  children:
    - name: Charlie
      age: 10
"@

        $obj = $yaml | ConvertFrom-Yaml -As ([MyClass])

        # Verify structure
        $obj.Family.Mom | Should -Not -BeNullOrEmpty
        $obj.Family.Dad | Should -BeNullOrEmpty
        $obj.Family.Children.Count | Should -Be 1

        # Serialize without -OmitNull
        $yaml1 = $obj | ConvertTo-Yaml
        $yaml1 | Should -Match "dad: null"

        # Serialize with -OmitNull
        $yaml2 = $obj | ConvertTo-Yaml -OmitNull
        $yaml2 | Should -Not -Match "dad:"
        $yaml2 | Should -Match "mom:"
        $yaml2 | Should -Match "children:"
    }

    It "Should emit all tags with -EmitTags on deeply nested objects" {
        $obj = [MyClass]::new()
        $obj.Title = "The Davis Family"
        $obj.Family = [Family]::new()
        $obj.Family.Mom = [Person]::new()
        $obj.Family.Mom.Name = "Lisa Davis"
        $obj.Family.Mom.Age = 38
        $obj.Family.Dad = [Person]::new()
        $obj.Family.Dad.Name = "Mike Davis"
        $obj.Family.Dad.Age = 40
        $obj.Family.Children = @(
            [Person]@{ Name = "Emma Davis"; Age = 12 }
        )

        $yaml = $obj | ConvertTo-Yaml -EmitTags

        # Verify tags on all levels
        $yaml | Should -Match "title: !!str The Davis Family"
        $yaml | Should -Match "name: !!str Lisa Davis"
        $yaml | Should -Match "age: !!int 38"
        $yaml | Should -Match "name: !!str Mike Davis"
        $yaml | Should -Match "age: !!int 40"
        $yaml | Should -Match "name: !!str Emma Davis"
        $yaml | Should -Match "age: !!int 12"
    }

    It "Should preserve metadata after modification and re-serialization" {
        $yaml = @"
title: Original Title
family:
  mom:
    name: Original Mom
    age: !!int 50
"@

        $obj = $yaml | ConvertFrom-Yaml -As ([MyClass])

        # Modify values
        $obj.Title = "Modified Title"
        $obj.Family.Mom.Age = 51

        # Add a comment
        $obj.Family.Mom.SetPropertyComment('Age', 'Updated age')

        # Serialize
        $newYaml = $obj | ConvertTo-Yaml

        # Original tag should still be there
        $newYaml | Should -Match "age: !!int 51"
        # New comment should be there
        $newYaml | Should -Match "# Updated age"
        # Modified values should be there
        $newYaml | Should -Match "title: Modified Title"
    }

    It "Should handle empty arrays vs null arrays correctly" {
        $yaml1 = @"
title: Family with no children
family:
  mom:
    name: Jane
    age: 30
  dad:
    name: John
    age: 32
  children: []
"@

        $obj1 = $yaml1 | ConvertFrom-Yaml -As ([MyClass])
        $null -eq $obj1.Family.Children | Should -Be $false
        $obj1.Family.Children.Count | Should -Be 0

        $yaml2 = @"
title: Family with null children
family:
  mom:
    name: Jane
    age: 30
  dad:
    name: John
    age: 32
  children: null
"@

        $obj2 = $yaml2 | ConvertFrom-Yaml -As ([MyClass])
        $null -eq $obj2.Family.Children | Should -Be $true

        # Serialize with -OmitNull
        $output1 = $obj1 | ConvertTo-Yaml -OmitNull
        $output1 | Should -Match "children:"  # Empty array is not omitted

        $output2 = $obj2 | ConvertTo-Yaml -OmitNull
        $output2 | Should -Not -Match "children:"  # Null is omitted
    }
}
