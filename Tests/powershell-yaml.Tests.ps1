# Copyright 2016 Cloudbase Solutions Srl
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

# pinning this module to an exact version, 
# because the options api will be merged with Assert-Equivalent
# before release of 1.0.0
Import-Module Assert -RequiredVersion 0.9.5

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleHome = Split-Path -Parent $here

$moduleName = "powershell-yaml"
$modulePath = Join-Path $moduleHome "powershell-yaml.psd1"
Import-Module $modulePath

InModuleScope $moduleName {
    $compareStrictly = Get-EquivalencyOption -Comparator Equality

    Describe "Test encode-decode symmetry." {

        Context "Simple-Items" {
            It "Should represent identity to encode and decode." -TestCases @(
                @{ Expected = 1 } 
                @{ Expected = "yes" } 
                @{ Expected = 56 } 
                @{ Expected = $null } 
            ) {
                param ($Expected)
                $actual = ConvertFrom-Yaml (ConvertTo-Yaml $Expected)

                Assert-Equivalent -Options $compareStrictly -Expected $Expected -Actual $actual 
            }
        }

        Context "Nulls and strings" {
            BeforeAll {
                $nullAndString = [ordered]@{"iAmNull"= $null; "iAmEmptyString"=""}
                $yaml = @"
iAmNull: 
iAmEmptyString: ""

"@
            }

            It "should preserve nulls and empty strings from PowerShell" {
                $toYaml = ConvertTo-Yaml $nullAndString
                $backFromYaml = ConvertFrom-Yaml $toYaml

                ($null -eq $backFromYaml.iAmNull) | Should -Be $true
                $backFromYaml.iAmEmptyString | Should -Be ""
                $toYaml | Should -Be $yaml
            }

            It "should preserve nulls and empty strings from Yaml" {
                $fromYaml = ConvertFrom-Yaml -Ordered $yaml
                $backToYaml = ConvertTo-Yaml $fromYaml

                $backToYaml | Should -Be $yaml
                ($null -eq $fromYaml.iAmNull) | Should -Be $true
                $fromYaml.iAmEmptyString | Should -Be ""
            }
        }

        Context "Test array handling under various circumstances." {
            $arr = 1, 2, "yes", @{ key = "value" }, 5, (1, "no", 3)

            It "Should represent identity to encode/decode arrays as arguments." {
                $yaml = ConvertTo-Yaml $arr
                $a = ConvertFrom-Yaml $yaml

                Assert-Equivalent -Options $compareStrictly -Actual $a -Expected $arr
            }

            It "Should represent identity to encode/decode arrays by piping them in." {
                $yaml = $arr | ConvertTo-Yaml
                $a = ConvertFrom-Yaml $yaml
                
                Assert-Equivalent -Options $compareStrictly -Actual $a -Expected $arr
            }

            It "Should be irrelevant whether we convert an array by piping it, or referencing them as an argument." {
                $arged = ConvertTo-Yaml $arr
                $piped = $arr | ConvertTo-Yaml

                Assert-Equivalent -Options $compareStrictly -Actual $piped -Expected $arged
            }
        }

        Context "Test merging parser" {
            $mergingYaml = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  value3: 3
"@

            $mergingYamlOverwriteCase = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  value1: 33
  value3: 3
"@

            It "Should expand merging key with appropriate referenced keys" {
                $result = ConvertFrom-Yaml -Yaml $mergingYaml -UseMergingParser
                [array]$values = $result.hoge.keys
                [array]::sort($values)
                Assert-Equivalent -Options $compareStrictly -Actual $values -Expected @("value1", "value2", "value3")
            }

            It "Should retain literal key name in the absence or -UseMergingParser" {
                $result = ConvertFrom-Yaml -Yaml $mergingYaml
                [array]$values = $result.hoge.keys
                [array]::sort($values)
                Assert-Equivalent -Options $compareStrictly -Actual $values -Expected @("<<", "value3")
            }

            It "Shoud Throw duplicate key exception when merging keys" {
                # This case does not seem to be treated by YamlDotNet and currently throws
                # a duplicate key exception
                { ConvertFrom-Yaml -Yaml $mergingYamlOverwriteCase -UseMergingParser } | Should -Throw -PassThru | Select-Object -ExpandProperty Exception | 
Should -BeLike "*Duplicate key*"
            }

        }

        Context "Test hash handling under various circumstances." {
            $hash = @{
                # NOTE: intentionally not considered as YAML requires dict keys
                # be strings. As such; decoding the encoding of this would result
                # in a hash with the string key of "1", as below:
                # 1 = 42;
                "1" = 42;
                today = @{
                    month = "January";
                    year = "2016";
                    timestamp = Get-Date
                };
                arr = 1, 2, 3, "yes", @{ yes = "yes" };
                yes = "no"
            }

            It "Should be symmetrical to encode and then decode the hash as an argument." {
                $yaml = ConvertTo-Yaml $hash
                $h = ConvertFrom-Yaml $yaml

                Assert-Equivalent -Options $compareStrictly -Actual $h -Expected $hash
            }

            It "Should be symmetrical to endocode and then decode a hash by piping it." {
                $yaml = $hash | ConvertTo-Yaml
                $h = ConvertFrom-Yaml $yaml

                Assert-Equivalent -Options $compareStrictly -Actual $h -Expected $hash
            }

            It "Shouldn't matter whether we reference or pipe our hashes in to the YAML functions." {
                $arged = ConvertTo-Yaml $hash
                $piped = $hash | ConvertTo-Yaml

                Assert-Equivalent -Options $compareStrictly -Actual $piped -Expected $arged
            }
        }

    }

    Describe "Being able to decode an externally provided string." {

        Context "Decoding an arbitrary YAML string correctly." {
            # testYaml is just a string containing some yaml to be tested below:
            $testYaml = @"
wishlist:
    - [coats, hats, and, scarves]
    - product     : A Cool Book.
      quantity    : 1
      description : I love that Cool Book.
      price       : 55.34
total: 4443.52
int64: $([int64]::MaxValue)
note: >
    I can't wait.
    To get that Cool Book.

dates:
    - 2001-12-15T02:59:43.1Z
    - 2001-12-14t21:59:43.10-05:00
    - 2001-12-14 21:59:43.10 -5
    - 2001-12-15 2:59:43.10
    - 2002-12-14
version:
    - 1.2.3
noniso8601dates:
    - 5/4/2017
    - 1.2.3
bools:
    - true
    - false
    - TRUE
    - FALSE
    - True
    - False
"@

            $expected = @{
                wishlist = @(
                    @("coats", "hats", "and", "scarves"),
                    @{
                        product = "A Cool Book.";
                        quantity = 1;
                        description = "I love that Cool Book.";
                        price = 55.34
                    }
                );
                total = 4443.52;
                int64 = ([int64]::MaxValue);
                note = ("I can't wait. To get that Cool Book.`n");
                dates = @(
                    [DateTime]::Parse('2001-12-15T02:59:43.1Z'),
                    [DateTime]::Parse('2001-12-14t21:59:43.10-05:00'),
                    [DateTime]::Parse('2001-12-14 21:59:43.10 -5'),
                    [DateTime]::Parse('2001-12-15 2:59:43.10'),
                    [DateTime]::Parse('2002-12-14')
                );
                version = "1.2.3";
                noniso8601dates = @( '5/4/2017', '1.2.3' );            
                bools = @( $true, $false, $true, $false, $true, $false );
            }

            $res = ConvertFrom-Yaml $testYaml

            It "Should decode the YAML string as expected." {
                $wishlist = $res['wishlist']
                $wishlist | Should -Not -BeNullOrEmpty
                $wishlist.Count | Should -Be 2
                $wishlist[0] | Should -Not -BeNullOrEmpty
                $wishlist[0].Count | Should -Be 4
                $wishlist[0][0] | Should -Be $expected['wishlist'][0][0]
                $wishlist[0][1] | Should -Be $expected['wishlist'][0][1]
                $wishlist[0][2] | Should -Be $expected['wishlist'][0][2]
                $wishlist[0][3] | Should -Be $expected['wishlist'][0][3]
                $product = $res['wishlist'][1]
                $product | Should -Not -BeNullOrEmpty
                $expectedProduct = $expected['wishlist'][1]
                $product['product'] | Should -Be $expectedProduct['product']
                $product['quantity'] | Should -Be $expectedProduct['quantity']
                $product['description'] | Should -Be $expectedProduct['description']
                $product['price'] | Should -Be $expectedProduct['price']
                $res['total'] | Should -Be $expected['total']
                $res['note'] | Should -Be $expected['note']

                $res['dates'] | Should -Not -BeNullOrEmpty
                $res['dates'].Count | Should -Be $expected['dates'].Count
                for( $idx = 0; $idx -lt $expected['dates'].Count; ++$idx )
                {
                    $res['dates'][$idx] | Should -BeOfType ([datetime])
                    $res['dates'][$idx] | Should -Be $expected['dates'][$idx]
                }

                $res['version'] | Should -BeOfType ([string])
                $res['version'] | Should -Be $expected['version']

                $res['noniso8601dates'] | Should -Not -BeNullOrEmpty
                $res['noniso8601dates'].Count | Should -Be $expected['noniso8601dates'].Count
                for( $idx = 0; $idx -lt $expected['noniso8601dates'].Count; ++$idx )
                {
                    $res['noniso8601dates'][$idx] | Should -BeOfType ([string])
                    $res['noniso8601dates'][$idx] | Should -Be $expected['noniso8601dates'][$idx]
                }
                
                Assert-Equivalent -Options $compareStrictly -Actual $res -Expected $expected
            }
        }

    }

    Describe "Test ConvertTo-Yaml -OutFile parameter behavior" {

        Context "Providing -OutFile with invalid prefix." {
            $testPath = "/some/bogus/path"
            $testObject = 42

            # mock Test-Path to fail so the test for the directory of the -OutFile fails:
            Mock Test-Path { return $false } -Verifiable -ParameterFilter { $OutFile -eq $testPath }

            It "Should refuse to work with an -OutFile with an invalid prefix." {
                { ConvertTo-Yaml $testObject -OutFile $testPath } | Should Throw "Parent folder for specified path does not exist"
            }

            It "Should verify that all the required mocks were called." {
                Assert-VerifiableMock
            }
        }

        Context "Providing existing -OutFile without -Force." {
            $testPath = "/some/bogus/path"
            $testObject = "A random string this time."

            # mock Test-Path to succeed so the -OutFile seems to exist:
            Mock Test-Path { return $true } -Verifiable -ParameterFilter { $OutFile -eq $testPath }

            It "Should refuse to work for an existing -OutFile but no -Force flag." {
                { ConvertTo-Yaml $testObject -OutFile $testPath } | Should Throw "Target file already exists. Use -Force to overwrite."
            }

            It "Should verify that all the required mocks were called." {
                Assert-VerifiableMock
            }
        }

        Context "Providing a valid -OutFile." {
            $testObject = @{ yes = "No"; "arr" = @(1, 2, 3) }
            $testPath = [System.IO.Path]::GetTempFileName()
            Remove-Item -Force $testPath # must be deleted for the test

            It "Should succesfully write the expected content to the specified -OutFile." {
                $yaml = ConvertTo-Yaml $testObject
                ConvertTo-Yaml $testObject -OutFile $testPath

                Compare-Object $yaml (Get-Content -Raw $testPath) | Should -Be $null

            }

            # NOTE: the below assertion relies on the above writing its file.
            It "Should succesfully write the expected content to the specified -OutFile with -Force even if it exists." {
                $newTestObject = @(1, "two", @("arr", "ay"), @{ yes = "no"; answer = 42 })

                $yaml = ConvertTo-Yaml  $newTestObject
                ConvertTo-Yaml $newTestObject -OutFile $testPath -Force

                Compare-Object $yaml (Get-Content -Raw $testPath) | Should -Be $null
            }
        }

    }
    
    Describe "Generic Casting Behaviour" {
        Context "Node Style is 'Plain'" {
            $value = @'
 T1: 001
'@
            It 'Should be an int' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -BeOfType System.Int32
            }
            
            It 'Should be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Be 1
            }
            
            It 'Should not be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Not -Be '001'
            }
        }
        
        Context "Node Style is 'SingleQuoted'" {
            $value = @'
 T1: '001'
'@
            It 'Should be a string' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -BeOfType System.String
            }
            
            It 'Should be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Be '001'
            }
            
            It 'Should not be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Not -Be '1'
            }
        }
        
        Context "Node Style is 'DoubleQuoted'" {
            $value = @'
 T1: "001"
'@
            It 'Should be a string' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -BeOfType System.String
            }
            
            It 'Should be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Be '001'
            }
            
            It 'Should not be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should -Not -Be '1'
            }
        }
    }

    Describe 'Strings containing other primitives' {
        Context 'String contains an int' {
            $value = @{key="1"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""1""$([Environment]::NewLine)"
            }
        }
        Context 'String contains a float' {
            $value = @{key="0.25"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""0.25""$([Environment]::NewLine)"
            }
        }
        Context 'String is "true"' {
            $value = @{key="true"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""true""$([Environment]::NewLine)"
            }
        }
        Context 'String is "false"' {
            $value = @{key="false"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""false""$([Environment]::NewLine)"
            }
        }
        Context 'String is "null"' {
            $value = @{key="null"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""null""$([Environment]::NewLine)"
            }
        }
        Context 'String is "~" (alternative syntax for null)' {
            $value = @{key="~"}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""~""$([Environment]::NewLine)"
            }
        }
        Context 'String is empty' {
            $value = @{key=""}
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: """"$([Environment]::NewLine)"
            }
        }
    }
}
