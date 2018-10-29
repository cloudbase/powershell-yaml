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
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleHome = Split-Path -Parent $here

$moduleName = "powershell-yaml"
$modulePath = Join-Path $moduleHome "powershell-yaml.psd1"
Import-Module $modulePath

InModuleScope $moduleName {

    # Confirm-Equality is a helper function which acts like a DeepEquals
    # with special attention payed to the specific types the yaml decoder
    # can handle.
    function Confirm-Equality {
        Param(
            [Parameter(Mandatory=$true)]$expected,
            [Parameter(Mandatory=$true)]$got
        )

        # check for easy way out; this should work for all simple value types:
        if ($expected -eq $got) {
            return $true
        }

        # else; handle hashes and arrays specially:
        if ($expected -is [System.Array]) {
            if ( -not (,$got | Get-Member -Name 'Count') -or ($expected.Count -ne $got.Count)) {
                return $false
            }

            # just iterate through the elements of the array comparing each one:
            for ($i = 0; $i -lt $expected.Count; $i = $i + 1) {
                if ( !(Confirm-Equality $expected[$i] $got[$i]) ) {
                    return $false
                }
            }

            return $true
        }

        if ($expected -is [Hashtable]) {
            if ($got -isnot [Hashtable] -or ($expected.Count -ne $got.Count)) {
                return $false
            }

            # iterate through all the keys:
            $eq = $true
            $expected.Keys | % {
                if ( !$got.ContainsKey($_) ) {
                    $eq = $false
                    return
                }

                if ( !(Confirm-Equality $expected.Item($_) $got.Item($_)) ) {
                    return $false
                }
            } | out-null

            return $eq
        }

        return $false
    }

    Describe "Test encode-decode symmetry." {

        Context "Simple-Items" {
            $items = 1, "yes", 56, $null

            foreach ($item in $items) {

                It "Should represent identity to encode and decode." {
                    $yaml = ConvertTo-Yaml $item
                    $i = ConvertFrom-Yaml $yaml

                    $item -eq $i | Should Be $true
                }

            }
        }

        Context "Test array handling under various circumstances." {
            $arr = 1, 2, "yes", @{ key = "value" }, 5, (1, "no", 3)

            It "Should represent identity to encode/decode arrays as arguments." {
                $yaml = ConvertTo-Yaml $arr
                $a = ConvertFrom-Yaml $yaml

                Confirm-Equality $arr $a | Should Be $true
            }

            It "Should represent identity to encode/decode arrays by piping them in." {
                $yaml = $arr | ConvertTo-Yaml
                $a = ConvertFrom-Yaml $yaml

                Confirm-Equality $arr $a | Should Be $true
            }

            It "Should be irrelevant whether we convert an array by piping it, or referencing them as an argument." {
                $arged = ConvertTo-Yaml $arr
                $piped = $arr | ConvertTo-Yaml

                Confirm-Equality $arged $piped | Should Be $true
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
                Confirm-Equality $values @("value1", "value2", "value3") | Should Be $true
            }

            It "Should retain literal key name in the absence or -UseMergingParser" {
                $result = ConvertFrom-Yaml -Yaml $mergingYaml
                [array]$values = $result.hoge.keys
                [array]::sort($values)
                Confirm-Equality $values @("<<", "value3") | Should Be $true
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

                Confirm-Equality $hash $h | Should Be $true
            }

            It "Should be symmetrical to endocode and then decode a hash by piping it." {
                $yaml = $hash | ConvertTo-Yaml
                $h = ConvertFrom-Yaml $yaml

                Confirm-Equality $hash $h | Should Be $true
            }

            It "Shouldn't matter whether we reference or pipe our hashes in to the YAML functions." {
                $arged = ConvertTo-Yaml $hash
                $piped = $hash | ConvertTo-Yaml

                Confirm-Equality $arged $piped | Should Be $true
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
    - yes
    - no
    - true
    - false
    - on
    - off

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
                $wishlist | Should Not BeNullOrEmpty
                $wishlist.Count | Should Be 2
                $wishlist[0] | Should Not BeNullOrEmpty
                $wishlist[0].Count | Should Be 4
                $wishlist[0][0] | Should Be $expected['wishlist'][0][0]
                $wishlist[0][1] | Should Be $expected['wishlist'][0][1]
                $wishlist[0][2] | Should Be $expected['wishlist'][0][2]
                $wishlist[0][3] | Should Be $expected['wishlist'][0][3]
                $product = $res['wishlist'][1]
                $product | Should Not BeNullOrEmpty
                $expectedProduct = $expected['wishlist'][1]
                $product['product'] | Should Be $expectedProduct['product']
                $product['quantity'] | Should Be $expectedProduct['quantity']
                $product['description'] | Should Be $expectedProduct['description']
                $product['price'] | Should Be $expectedProduct['price']
                $res['total'] | Should Be $expected['total']
                $res['note'] | Should Be $expected['note']

                $res['dates'] | Should Not BeNullOrEmpty
                $res['dates'].Count | Should Be $expected['dates'].Count
                for( $idx = 0; $idx -lt $expected['dates'].Count; ++$idx )
                {
                    $res['dates'][$idx] | Should BeOfType ([datetime])
                    $res['dates'][$idx] | Should Be $expected['dates'][$idx]
                }

                $res['version'] | Should BeOfType ([string])
                $res['version'] | Should Be $expected['version']

                $res['noniso8601dates'] | Should Not BeNullOrEmpty
                $res['noniso8601dates'].Count | Should Be $expected['noniso8601dates'].Count
                for( $idx = 0; $idx -lt $expected['noniso8601dates'].Count; ++$idx )
                {
                    $res['noniso8601dates'][$idx] | Should BeOfType ([string])
                    $res['noniso8601dates'][$idx] | Should Be $expected['noniso8601dates'][$idx]
                }
                
                Confirm-Equality $expected $res | Should Be $true
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

                Compare-Object $yaml (Get-Content -Raw $testPath) | Should Be $null

            }

            # NOTE: the below assertion relies on the above writing its file.
            It "Should succesfully write the expected content to the specified -OutFile with -Force even if it exists." {
                $newTestObject = @(1, "two", @("arr", "ay"), @{ yes = "no"; answer = 42 })

                $yaml = ConvertTo-Yaml  $newTestObject
                ConvertTo-Yaml $newTestObject -OutFile $testPath -Force

                Compare-Object $yaml (Get-Content -Raw $testPath) | Should Be $null
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
                $result.T1 | Should BeOfType System.Int32
            }
            
            It 'Should be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Be 1
            }
            
            It 'Should not be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Not Be '001'
            }
        }
        
        Context "Node Style is 'SingleQuoted'" {
            $value = @'
 T1: '001'
'@
            It 'Should be a string' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should BeOfType System.String
            }
            
            It 'Should be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Be '001'
            }
            
            It 'Should not be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Not Be '1'
            }
        }
        
        Context "Node Style is 'DoubleQuoted'" {
            $value = @'
 T1: "001"
'@
            It 'Should be a string' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should BeOfType System.String
            }
            
            It 'Should be value of 001' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Be '001'
            }
            
            It 'Should not be value of 1' {
                $result = ConvertFrom-Yaml -Yaml $value
                $result.T1 | Should Not Be '1'
            }
        }
    }
}
