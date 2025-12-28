Import-Module $PSScriptRoot/../powershell-yaml.psd1 -Force

Describe 'YamlDocumentParser Metadata Preservation Tests' {
    BeforeAll {
        # The module will load the assemblies automatically
        # We just need to ensure YamlDocumentParser type is available
        # Get a dummy conversion to ensure assemblies are loaded
        $null = ConvertFrom-Yaml "test: value"
    }

    Context 'Basic Metadata Parsing' {
        It 'Should parse simple YAML document' {
            $yaml = @"
name: John
age: 30
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1 | Should -Not -BeNullOrEmpty
            $result.Item1['name'] | Should -Be 'John'
            $result.Item1['age'] | Should -Be 30
            $result.Item2 | Should -Not -BeNullOrEmpty
        }

        It 'Should parse nested YAML structure' {
            $yaml = @"
person:
  name: John
  age: 30
  address:
    city: New York
    zip: 10001
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1 | Should -Not -BeNullOrEmpty
            $result.Item1['person']['name'] | Should -Be 'John'
            $result.Item1['person']['address']['city'] | Should -Be 'New York'
            $result.Item2 | Should -Not -BeNullOrEmpty
        }

        It 'Should parse YAML with sequences' {
            $yaml = @"
items:
  - apple
  - banana
  - cherry
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1 | Should -Not -BeNullOrEmpty
            $result.Item1['items'] | Should -HaveCount 3
            $result.Item1['items'][0] | Should -Be 'apple'
            $result.Item1['items'][1] | Should -Be 'banana'
            $result.Item1['items'][2] | Should -Be 'cherry'
        }

        It 'Should handle null values' {
            $yaml = @"
name: John
middle: null
age: 30
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1 | Should -Not -BeNullOrEmpty
            $result.Item1['name'] | Should -Be 'John'
            $result.Item1['middle'] | Should -BeNullOrEmpty
            $result.Item1['age'] | Should -Be 30
        }

        It 'Should handle boolean values' {
            $yaml = @"
enabled: true
disabled: false
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1['enabled'] | Should -Be $true
            $result.Item1['disabled'] | Should -Be $false
        }

        It 'Should handle numeric values' {
            $yaml = @"
integer: 42
long: 9223372036854775807
decimal: 3.14159
"@
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1['integer'] | Should -Be 42
            $result.Item1['integer'] | Should -BeOfType [int]
            $result.Item1['long'] | Should -Be 9223372036854775807
            $result.Item1['decimal'] | Should -Be 3.14159
        }

        It 'Should return null for empty document' {
            $yaml = ""
            $result = [YamlDocumentParser]::ParseWithMetadata($yaml)
            $result.Item1 | Should -BeNullOrEmpty
            $result.Item2 | Should -BeNullOrEmpty
        }
    }

    Context 'Metadata Store Tests' {
        It 'Should create and retrieve property comments' {
            $store = New-Object YamlMetadataStore
            $store.SetPropertyComment('name', 'User name')
            $comment = $store.GetPropertyComment('name')
            $comment | Should -Be 'User name'
        }

        It 'Should return null for non-existent property comment' {
            $store = New-Object YamlMetadataStore
            $comment = $store.GetPropertyComment('nonexistent')
            $comment | Should -BeNullOrEmpty
        }

        It 'Should create and retrieve property tags' {
            $store = New-Object YamlMetadataStore
            $store.SetPropertyTag('value', 'tag:yaml.org,2002:str')
            $tag = $store.GetPropertyTag('value')
            $tag | Should -Be 'tag:yaml.org,2002:str'
        }

        It 'Should create nested metadata stores' {
            $store = New-Object YamlMetadataStore
            $nested = $store.GetNestedMetadata('person')
            $nested | Should -Not -BeNullOrEmpty
            $nested.SetPropertyComment('name', 'Person name')
            $nested.GetPropertyComment('name') | Should -Be 'Person name'
        }
    }
}
