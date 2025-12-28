Import-Module $PSScriptRoot/../powershell-yaml.psd1 -Force

Describe 'Round-Trip Comment Preservation Tests' {
    It 'Should preserve block comments through round-trip' {
        $yaml = @"
# User's full name
name: John
# User's age
age: 30
"@
        $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
        
        # Modify a value
        $obj.age = 31
        
        # Convert back to YAML
        $newYaml = ConvertTo-Yaml $obj
        
        # Comments should be preserved
        $newYaml | Should -Match "# User's full name"
        $newYaml | Should -Match "# User's age"
        $newYaml | Should -Match "age: 31"
    }
    
    It 'Should preserve programmatically-set comments through round-trip' {
        $yaml = @"
name: John
age: 30
"@
        $obj = ConvertFrom-Yaml $yaml -As ([PSCustomObject])
        
        # Add comments programmatically
        $obj | Set-YamlPropertyComment -PropertyName 'name' -Comment 'Full name of user'
        $obj | Set-YamlPropertyComment -PropertyName 'age' -Comment 'Age in years'
        
        # Convert to YAML
        $newYaml = ConvertTo-Yaml $obj
        
        # Comments should be in output
        $newYaml | Should -Match "# Full name of user"
        $newYaml | Should -Match "# Age in years"
    }
}
