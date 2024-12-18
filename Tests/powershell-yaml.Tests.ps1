# Copyright 2016-2024 Cloudbase Solutions Srl
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
Import-Module Assert -Version 0.9.6

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleHome = Split-Path -Parent $here

$moduleName = "powershell-yaml"
$modulePath = Join-Path $moduleHome "powershell-yaml.psd1"
Import-Module $modulePath

InModuleScope $moduleName {
    $compareStrictly = Get-EquivalencyOption -Comparator Equality

    Describe "Test flow styles" {
        Context "Mappings, sequences and PSCustomObjects" {
            It "Should serialize Block flow (default) correctly" {
                $obj = [ordered]@{
                    aStringKey = "test"
                    anIntKey = 1
                    anArrayKey = @(1, 2, 3)
                }
                $expected = @"
aStringKey: test
anIntKey: 1
anArrayKey:
- 1
- 2
- 3

"@
                $serialized = ConvertTo-Yaml $obj
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized

                $pso = [pscustomobject]$obj
                $serialized = ConvertTo-Yaml $pso
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized
            }

            It "Should serialize Flow flow correctly" {
                $obj = [ordered]@{
                    aStringKey = "test"
                    anIntKey = 1
                    anArrayKey = @(1, 2, 3)
                }
                $expected = @"
{aStringKey: test, anIntKey: 1, anArrayKey: [1, 2, 3]}

"@
                $serialized = ConvertTo-Yaml -Options UseFlowStyle $obj
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized

                $pso = [pscustomobject]$obj
                $serialized = ConvertTo-Yaml -Options UseFlowStyle $pso
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized
            }

            It "Should serialize SequenceFlowStyle correctly" {
                $obj = [ordered]@{
                    aStringKey = "test"
                    anIntKey = 1
                    anArrayKey = @(1, 2, 3)
                }
                $expected = @"
aStringKey: test
anIntKey: 1
anArrayKey: [1, 2, 3]

"@
                $serialized = ConvertTo-Yaml -Options UseSequenceFlowStyle $obj
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized

                $pso = [pscustomobject]$obj
                $serialized = ConvertTo-Yaml -Options UseSequenceFlowStyle $pso
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized
            }

            It "Should serialize JsonCompatible correctly" {
                $obj = [ordered]@{
                    aStringKey = "test"
                    anIntKey = 1
                    anArrayKey = @(1, 2, 3)
                }
                $expected = @"
{"aStringKey": "test", "anIntKey": 1, "anArrayKey": [1, 2, 3]}

"@
                $serialized = ConvertTo-Yaml -Options JsonCompatible $obj
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized

                if ($PSVersionTable['PSEdition'] -eq 'Core') {
                    $deserializedWithJSonCommandlet = $serialized | ConvertFrom-Json -AsHashtable
                    Assert-Equivalent -Options $compareStrictly -Expected $obj -Actual $deserializedWithJSonCommandlet
                }

                $pso = [pscustomobject]$obj
                $serialized = ConvertTo-Yaml -Options JsonCompatible $pso
                Assert-Equivalent -Options $compareStrictly -Expected $expected -Actual $serialized

                if ($PSVersionTable['PSEdition'] -eq 'Core') {
                    $deserializedWithJSonCommandlet = $serialized | ConvertFrom-Json -AsHashtable
                    Assert-Equivalent -Options $compareStrictly -Expected $obj -Actual $deserializedWithJSonCommandlet
                }
            }
        }
    }

    Describe "Test PSCustomObject wrapped values are serialized correctly" {
        Context "A PSCustomObject containing nested PSCustomObjects" {
            It "Should serialize correctly" {
                $expectBigInt = [System.Numerics.BigInteger]::Parse("9999999999999999999999999999999999999999999999999")
                $obj = [PSCustomObject]@{a = Write-Output 'string'; b = Write-Output 1; c = Write-Output @{nested = $true};d = [pscustomobject]$expectBigInt}
                $asYaml = ConvertTo-Yaml $obj
                $fromYaml = ConvertFrom-Yaml $asYaml

                Assert-Equivalent -Options $compareStrictly -Expected "string" -Actual $fromYaml["a"]
                Assert-Equivalent -Options $compareStrictly -Expected 1 -Actual $fromYaml["b"]
                Assert-Equivalent -Options $compareStrictly -Expected $expectBigInt -Actual $fromYaml["d"]
            }
        }

        Context "A hashtable containing nested PSCustomObjects" {
            It "Should serialize correctly" {
                $expectBigInt = [System.Numerics.BigInteger]::Parse("9999999999999999999999999999999999999999999999999")
                $obj = @{a = Write-Output 'string'; b = Write-Output 1; c = Write-Output @{nested = $true};d = [pscustomobject]$expectBigInt}
                $asYaml = ConvertTo-Yaml $obj
                $fromYaml = ConvertFrom-Yaml $asYaml

                Assert-Equivalent -Options $compareStrictly -Expected "string" -Actual $fromYaml["a"]
                Assert-Equivalent -Options $compareStrictly -Expected 1 -Actual $fromYaml["b"]
                Assert-Equivalent -Options $compareStrictly -Expected $expectBigInt -Actual $fromYaml["d"]
            }
        }

        Context "A generic dictionary containing nested PSCustomObjects" {
            It "Should serialize correctly" {
                $expectBigInt = [System.Numerics.BigInteger]::Parse("9999999999999999999999999999999999999999999999999")
                $obj = [System.Collections.Generic.Dictionary[string, object]]::new()
                $obj["a"] = Write-Output 'string'
                $obj["b"] = Write-Output 1
                $obj["c"] = Write-Output @{nested = $true}
                $obj["d"] = [pscustomobject]$expectBigInt

                $asYaml = ConvertTo-Yaml $obj
                $fromYaml = ConvertFrom-Yaml $asYaml

                Assert-Equivalent -Options $compareStrictly -Expected "string" -Actual $fromYaml["a"]
                Assert-Equivalent -Options $compareStrictly -Expected 1 -Actual $fromYaml["b"]
                Assert-Equivalent -Options $compareStrictly -Expected $expectBigInt -Actual $fromYaml["d"]
            }
        }
    }

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
                $global:nullAndString = [ordered]@{"iAmNull"= $null; "iAmEmptyString"=""}
                $global:yaml = @"
iAmNull: 
iAmEmptyString: ""

"@
            }

            It "should not serialize null value when -Options OmitNullValues is set" {
                $toYaml = ConvertTo-Yaml $nullAndString -Options OmitNullValues
                $toYaml | Should -Be "iAmEmptyString: """"$([Environment]::NewLine)"
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
            BeforeAll {
                $global:mergingYaml = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  value3: 3
"@

                $global:mergingYamlOverwriteCase = @"
---
default: &default
  value1: 1
  value2: 2

hoge:
  <<: *default
  value1: 33
  value3: 3
"@
            }

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
            BeforeAll {
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

intsAndDecimals:
    aStringTatLooksLikeAFloat: 55,34
    aStringThatLooksLikeAnInt: 2018+
    scientificNotationInt: 1e+3
    scientificNotationBigInt: 1e+40
    intWithTag: !!int "42"
    zeroIntWithTag: !!int "0"
    zeroIntWithoutTag: 0
    scientificNotationIntWithTag: !!int "1e+3"
    aDecimalWithATag: !!float "3.9999999999999990"
    aDecimalWithoutATag: 3.9999999999999990
    decimalInfinity: !!float ".inf"
    decimalNegativeInfinity: !!float "-.inf"

dates:
    - !!timestamp 2001-12-15T02:59:43.1Z
    - !!timestamp 2001-12-14t21:59:43.10-05:00
    - !!timestamp 2001-12-14 21:59:43.10 -5
    - !!timestamp 2001-12-15 2:59:43.10
    - !!timestamp 2002-12-14
datesAsStrings:
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
            
                $global:expected = @{
                    wishlist = @(
                        @("coats", "hats", "and", "scarves"),
                        @{
                            product = "A Cool Book.";
                            quantity = 1;
                            description = "I love that Cool Book.";
                            price = 55.34;
                        }
                    );
                    intsAndDecimals = @{
                            aStringTatLooksLikeAFloat = "55,34";
                            aStringThatLooksLikeAnInt = "2018+"
                            scientificNotationInt = [int32]1000
                            scientificNotationBigInt = [System.Numerics.BigInteger]::Parse("10000000000000000000000000000000000000000")
                            intWithTag = 42
                            zeroIntWithTag = 0
                            zeroIntWithoutTag = 0
                            scientificNotationIntWithTag = 1000
                            aDecimalWithATag = [decimal]::Parse("3.9999999999999990", [System.Globalization.CultureInfo]::InvariantCulture)
                            aDecimalWithoutATag = [decimal]::Parse("3.9999999999999990", [System.Globalization.CultureInfo]::InvariantCulture)
                            decimalInfinity = [double]::PositiveInfinity
                            decimalNegativeInfinity = [double]::NegativeInfinity
                    }
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
                    datesAsStrings = @(
                        "2001-12-15T02:59:43.1Z",
                        "2001-12-14t21:59:43.10-05:00",
                        "2001-12-14 21:59:43.10 -5",
                        "2001-12-15 2:59:43.10",
                        "2002-12-14"
                    );
                    version = "1.2.3";
                    noniso8601dates = @( '5/4/2017', '1.2.3' );            
                    bools = @( $true, $false, $true, $false, $true, $false );
                }

                $global:res = ConvertFrom-Yaml $testYaml
            }

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

                $expectedIntsAndDecimals = $expected['intsAndDecimals']

                $intsAndDecimals = $res['intsAndDecimals']
                $intsAndDecimals['aStringTatLooksLikeAFloat'] | Should -Be $expectedIntsAndDecimals['aStringTatLooksLikeAFloat']
                $intsAndDecimals['aStringTatLooksLikeAFloat'] | Should -BeOfType ([string])
                $intsAndDecimals['aStringThatLooksLikeAnInt'] | Should -Be $expectedIntsAndDecimals['aStringThatLooksLikeAnInt']
                $intsAndDecimals['aStringThatLooksLikeAnInt'] | Should -BeOfType ([string])
                $intsAndDecimals['zeroIntWithTag'] | Should -Be $expectedIntsAndDecimals['zeroIntWithTag']
                $intsAndDecimals['zeroIntWithTag'] | Should -BeOfType ([int32])
                $intsAndDecimals['zeroIntWithoutTag'] | Should -Be $expectedIntsAndDecimals['zeroIntWithoutTag']
                $intsAndDecimals['zeroIntWithoutTag'] | Should -BeOfType ([int32])
                $intsAndDecimals['scientificNotationInt'] | Should -Be $expectedIntsAndDecimals['scientificNotationInt']
                $intsAndDecimals['scientificNotationInt'] | Should -BeOfType ([int32])
                $intsAndDecimals['scientificNotationBigInt'] | Should -Be $expectedIntsAndDecimals['scientificNotationBigInt']
                $intsAndDecimals['scientificNotationBigInt'] | Should -BeOfType ([System.Numerics.BigInteger])
                $intsAndDecimals['intWithTag'] | Should -Be $expectedIntsAndDecimals['intWithTag']
                $intsAndDecimals['intWithTag'] | Should -BeOfType ([int32])
                $intsAndDecimals['scientificNotationIntWithTag'] | Should -Be $expectedIntsAndDecimals['scientificNotationIntWithTag']
                $intsAndDecimals['scientificNotationIntWithTag'] | Should -BeOfType ([int32])
                $intsAndDecimals['aDecimalWithATag'] | Should -Be $expectedIntsAndDecimals['aDecimalWithATag']
                $intsAndDecimals['aDecimalWithATag'] | Should -BeOfType ([decimal])
                $intsAndDecimals['aDecimalWithoutATag'] | Should -Be $expectedIntsAndDecimals['aDecimalWithoutATag']
                $intsAndDecimals['aDecimalWithoutATag'] | Should -BeOfType ([decimal])
                $intsAndDecimals['decimalInfinity'] | Should -Be $expectedIntsAndDecimals['decimalInfinity']
                $intsAndDecimals['decimalInfinity'] | Should -BeOfType ([double])
                $intsAndDecimals['decimalNegativeInfinity'] | Should -Be $expectedIntsAndDecimals['decimalNegativeInfinity']
                $intsAndDecimals['decimalNegativeInfinity'] | Should -BeOfType ([double])

                $res['dates'] | Should -Not -BeNullOrEmpty
                $res['dates'].Count | Should -Be $expected['dates'].Count
                for( $idx = 0; $idx -lt $expected['dates'].Count; ++$idx )
                {
                    $res['dates'][$idx] | Should -BeOfType ([datetime])
                    $res['dates'][$idx] | Should -Be $expected['dates'][$idx]
                }

                $res['datesAsStrings'] | Should -Not -BeNullOrEmpty
                $res['datesAsStrings'].Count | Should -Be $expected['datesAsStrings'].Count
                for( $idx = 0; $idx -lt $expected['datesAsStrings'].Count; ++$idx )
                {
                    $res['datesAsStrings'][$idx] | Should -BeOfType ([string])
                    $res['datesAsStrings'][$idx] | Should -Be $expected['dates'][$idx]
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

    Describe "Test ConvertTo-Yaml can serialize more complex nesting" {
        BeforeAll {
            $global:sample = [PSCustomObject]@{
                a1 = "a"
                a2 = [PSCustomObject]@{
                    "a1" = "a"
                    a2 = [PSCustomObject]@{
                    a1 = [PSCustomObject]@{
                        "a1" = "a"
                        a2 = [PSCustomObject]@{
                        a1 = "a"
                        }
                        a3 = [ordered]@{
                        a1 = @("a", "b")
                        }
                        a4 = @("a", "b")
                    }
                    }
                    a3 = @(
                    [PSCustomObject]@{
                        a1 = "a"
                        a2 = $False
                    }
                    )
                }
            }

            $global:sample2 = [PSCustomObject]@{
                b1 = "b"
                b2 = [PSCustomObject]@{
                  b1 = "b"
                  b2 = [PSCustomObject]@{
                    "b" = "b"
                  }
                }
                b3 = [ordered]@{
                    b1 = @("b1", "b2")
                }
                b4 = $True
                b5 = [PSCustomObject]@{
                    b = "b"
                }
            }

            $global:expected_json = '{"a1":"a","a2":{"a1":"a","a2":{"a1":{"a1":"a","a2":{"a1":"a"},"a3":{"a1":["a","b"]},"a4":["a","b"]}},"a3":[{"a1":"a","a2":false}]}}'
            $global:expected_json2 = '{"b1":"b","b2":{"b1":"b","b2":{"b":"b"}},"b3":{"b1":["b1","b2"]},"b4":true,"b5":{"b":"b"}}'
            $global:expected_block_yaml = @"
a1: a
a2:
  a1: a
  a2:
    a1:
      a1: a
      a2:
        a1: a
      a3:
        a1:
        - a
        - b
      a4:
      - a
      - b
  a3:
  - a1: a
    a2: false

"@

            $global:expected_flow_yaml = '{a1: a, a2: {a1: a, a2: {a1: {a1: a, a2: {a1: a}, a3: {a1: [a, b]}, a4: [a, b]}}, a3: [{a1: a, a2: false}]}}'
            $global:expected_block_yaml2 = @"
b1: b
b2:
  b1: b
  b2:
    b: b
b3:
  b1:
  - b1
  - b2
b4: true
b5:
  b: b

"@
            $global:expected_flow_yaml2 = '{b1: b, b2: {b1: b, b2: {b: b}}, b3: {b1: [b1, b2]}, b4: true, b5: {b: b}}'
        }

        It "Should serialize nested PSCustomObjects to YAML" {
            $yaml = ConvertTo-Yaml $sample
            $yaml | Should -Be $expected_block_yaml

            $yaml = ConvertTo-Yaml $sample2
            $yaml | Should -Be $expected_block_yaml2
        }

        It "Should serialize nested PSCustomObjects to YAML flow format" {
            $yaml = ConvertTo-Yaml $sample -Options UseFlowStyle
            $yaml.Replace($([Environment]::NewLine), "") | Should -Be $expected_flow_yaml

            $yaml = ConvertTo-Yaml $sample2 -Options UseFlowStyle
            $yaml.Replace($([Environment]::NewLine), "") | Should -Be $expected_flow_yaml2
        }

        It "Should serialize nested PSCustomObjects to JSON" {
            # Converted with powershell-yaml
            $json = ConvertTo-Yaml $sample -Options JsonCompatible
            $json.Replace(" ", "").Replace($([Environment]::NewLine), "") | Should -Be $expected_json

            # Converted with ConvertTo-Json
            $withJsonCommandlet = ConvertTo-Json -Compress -Depth 100 $sample
            $withJsonCommandlet | Should -Be $expected_json

            # Converted with powershell-yaml
            $json = ConvertTo-Yaml $sample2 -Options JsonCompatible
            $json.Replace(" ", "").Replace($([Environment]::NewLine), "") | Should -Be $expected_json2

            # Converted with ConvertTo-Json
            $withJsonCommandlet = ConvertTo-Json -Compress -Depth 100 $sample2
            $withJsonCommandlet | Should -Be $expected_json2
        }
    }

    Describe "Test ConvertTo-Yaml -OutFile parameter behavior" {

        Context "Providing -OutFile with invalid prefix." {
            BeforeAll {
                $testPath = "/some/bogus/path"
                $global:testObject = 42
                # mock Test-Path to fail so the test for the directory of the -OutFile fails:
                Mock Test-Path { return $false } -Verifiable -ParameterFilter { $OutFile -eq $testPath }
            }

            It "Should refuse to work with an -OutFile with an invalid prefix." {
                { ConvertTo-Yaml $testObject -OutFile $testPath } | Should -Throw "Parent folder for specified path does not exist"
            }

            It "Should verify that all the required mocks were called." {
                Assert-VerifiableMock
            }
        }

        Context "Providing existing -OutFile without -Force." {
            BeforeAll {
                $testPath = "/some/bogus/path"
                $global:testObject = "A random string this time."
                # mock Test-Path to succeed so the -OutFile seems to exist:
                Mock Test-Path { return $true } -Verifiable -ParameterFilter { $OutFile -eq $testPath }
            }

            It "Should refuse to work for an existing -OutFile but no -Force flag." {
                { ConvertTo-Yaml $testObject -OutFile $testPath } | Should -Throw "Target file already exists. Use -Force to overwrite."
            }

            It "Should verify that all the required mocks were called." {
                Assert-VerifiableMock
            }
        }

        Context "Providing a valid -OutFile." {
            BeforeAll {
                $global:testObject = @{ yes = "No"; "arr" = @(1, 2, 3) }
                $testPath = [System.IO.Path]::GetTempFileName()
                Remove-Item -Force $testPath # must be deleted for the test
            }

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
            BeforeAll {
                $global:value = @'
 T1: 001
'@
            }

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
            BeforeAll {
                $global:value = @'
 T1: '001'
'@
            }

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
            BeforeAll {
                $global:value = @'
 T1: "001"
'@
            }
            
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
            BeforeAll {
                $global:value = @{key="1"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""1""$([Environment]::NewLine)"
            }
        }
        Context 'String contains a float' {
            BeforeAll {
                $global:value = @{key="0.25"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""0.25""$([Environment]::NewLine)"
            }
        }
        Context 'String is "true"' {
            BeforeAll {
                $global:value = @{key="true"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""true""$([Environment]::NewLine)"
            }
        }
        Context 'String is "false"' {
            BeforeAll {
                $global:value = @{key="false"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""false""$([Environment]::NewLine)"
            }
        }
        Context 'String is "null"' {
            BeforeAll {
                $global:value = @{key="null"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""null""$([Environment]::NewLine)"
            }
        }
        Context 'String is "~" (alternative syntax for null)' {
            BeforeAll {
                $global:value = @{key="~"}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: ""~""$([Environment]::NewLine)"
            }
        }
        Context 'String is empty' {
            BeforeAll {
                $global:value = @{key=""}
            }
            It 'Should serialise with double quotes' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: """"$([Environment]::NewLine)"
            }
        }
    }

    Describe 'Numbers are parsed as the smallest type possible' {
        BeforeAll {
            $global:value = @'
bigInt: 99999999999999999999999999999999999
int32: 2147483647
int64: 9223372036854775807
decimal: 3.10
reallyLongDecimal: 3.9999999999999990
'@
        }

        It 'Should be a BigInt' {
            $result = ConvertFrom-Yaml -Yaml $value
            $result.bigInt | Should -BeOfType System.Numerics.BigInteger
        }

        It "Should round-trip decimals with trailing 0" {
            $result = ConvertFrom-Yaml -Yaml $value
            $result.decimal | Should -Be ([decimal]3.10)
            $result.reallyLongDecimal | Should -Be ([decimal]::Parse("3.9999999999999990", [cultureinfo]::InvariantCulture))

            ConvertTo-Yaml $result["decimal"] | Should -Be "3.10$([Environment]::NewLine)"
            ConvertTo-Yaml $result["reallyLongDecimal"] | Should -Be "3.9999999999999990$([Environment]::NewLine)"
        }

        It 'Should be of proper type and value' {
            $result = ConvertFrom-Yaml -Yaml $value
            $result.bigInt | Should -Be ([System.Numerics.BigInteger]::Parse("99999999999999999999999999999999999"))
            $result.int32 | Should -Be ([int32]2147483647)
            $result.int64 | Should -Be ([int64]9223372036854775807)
            $result.decimal | Should -Be ([decimal]3.10)
        }
    }

    Describe 'PSCustomObjects' {
        Context 'Classes with PSCustomObjects' {
            It 'Should serialise as a hash' {
                $nestedPsO = [PSCustomObject]@{
                    Nested = 'NestedValue'
                }
                $nestedHashTable = @{
                    "aKey" = $nestedPsO
                }
                $nestedArray = @(
                    $nestedPsO
                )
                $PsO = [PSCustomObject]@{
                    Name = 'Value'
                    Nested = $nestedPsO
                    NestedHashTable = $nestedHashTable
                    NestedArray = $nestedArray
                    NullValue = $null
                }

                class TestClass {
                    [PSCustomObject]$PsO
                    [string]$Ok
                }
                $Class = [TestClass]@{
                    PsO = $PsO
                    Ok  = 'aye'
                }
                $asYaml = ConvertTo-Yaml $Class
                $result = ConvertFrom-Yaml -Yaml $asYaml -Ordered
                [System.Collections.Specialized.OrderedDictionary]$ret = [System.Collections.Specialized.OrderedDictionary]::new()
                $ret["PsO"] = [System.Collections.Specialized.OrderedDictionary]::new()
                $ret["PsO"]["Name"] = "Value"
                $ret["PsO"]["Nested"] = [System.Collections.Specialized.OrderedDictionary]::new()
                $ret["PsO"]["Nested"]["Nested"] = "NestedValue"
                $ret["PsO"]["NestedHashTable"] = [ordered]@{
                    "aKey" = [ordered]@{
                        "Nested" = "NestedValue"
                    }
                }
                $ret["PsO"]["NestedArray"] = @(
                    [ordered]@{
                        "Nested" = "NestedValue"
                    }
                )
                $ret["PsO"]["NullValue"] = $null
                $ret["Ok"] = "aye"
                Assert-Equivalent -Options $compareStrictly -Expected $ret -Actual $result
            }
        }

        Context 'PSObject with null value is skipped when -Options OmitNullValues' {
            BeforeAll {
                $global:value = [PSCustomObject]@{
                    key1 = "value1"
                    key2 = $null
                }
            }
            It 'Should serialise as a hash with only the non-null value' {
                $result = ConvertTo-Yaml $value -Options OmitNullValues
                $result | Should -Be "key1: value1$([Environment]::NewLine)"
            }
        }

        Context 'PSObject with null value is included when -Options OmitNullValues is not set' {
            BeforeAll {
                $global:value = [PSCustomObject]@{
                    key1 = "value1"
                    key2 = $null
                }
            }
            It 'Should serialise as a hash with the null value' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key1: value1$([Environment]::NewLine)key2: $null$([Environment]::NewLine)"
            }
        }

        Context 'PSCustomObject with a single property' {
            BeforeAll {
                $global:value = [PSCustomObject]@{key="value"}
            }
            It 'Should serialise as a hash' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key: value$([Environment]::NewLine)"
            }
        }
        Context 'PSCustomObject with multiple properties' {
            BeforeAll {
                $global:value = [PSCustomObject]@{key1="value1"; key2="value2"}
            }
            It 'Should serialise as a hash' {
                $result = ConvertTo-Yaml $value
                $result | Should -Be "key1: value1$([Environment]::NewLine)key2: value2$([Environment]::NewLine)"
            }
            It 'Should deserialise as a hash' {
                $asYaml = ConvertTo-Yaml $value
                $result = ConvertFrom-Yaml -Yaml $asYaml -Ordered
                Assert-Equivalent -Options $compareStrictly -Expected @{key1="value1"; key2="value2"} -Actual ([hashtable]$result)
            }
        }
    }

    Describe 'StringQuotingEmitter' {
        BeforeAll {
            $oldYamlPkgUrl = 'https://www.nuget.org/api/v2/package/YamlDotNet/11.2.1'
            $pkgPath = Join-Path -Path $TestDrive -ChildPath 'YamlDotNet-11.2.1.nupkg'
            $oldYamlPkgDirPath = Join-Path -Path $TestDrive -ChildPath 'YamlDotNet-11.2.1'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $oldYamlPkgUrl -UseBasicParsing -OutFile $pkgPath
            New-Item -Path $oldYamlPkgDirPath -ItemType Directory
            Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
            [IO.Compression.ZipFile]::ExtractToDirectory($pkgPath, $oldYamlPkgDirPath)
        }

        $targetFrameworks = @('net45', 'netstandard1.3')
        if ($PSVersionTable['PSEdition'] -eq 'Core')
        {
            $targetFrameworks = @('netstandard1.3', 'netstandard2.1')
        }

        It 'can be compiled on import with <_>/YamlDotNet.dll loaded' -ForEach $targetFrameworks {
            $targetFramework = $_
            $yamlDotnetAssemblyPath =
                Join-Path -Path $TestDrive -ChildPath "YamlDotNet-11.2.1\lib\${targetFramework}\YamlDotNet.dll" -Resolve
            $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\powershell-yaml.psd1' -Resolve

            {
                # Do this in the background because YamlDotNet.dll is already loaded in this session and the way we
                # found to reproduce this issue is by loading YamlDotNet 11.2.1 then importing powershell-yaml.
                Start-Job {
                    $yamlDotnetAssemblyPath = $using:yamlDotnetAssemblyPath
                    $modulePath = $using:modulePath

                    Add-Type -Path $yamlDotnetAssemblyPath
                    Import-Module $modulePath
                } | Receive-Job -Wait -AutoRemoveJob -ErrorAction Stop
            } | Should -Not -Throw
        }
    }
}
