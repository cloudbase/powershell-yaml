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
            if ($got -isnot [System.Array] -or ($expected.Count -ne $got.Count)) {
                return $false
            }

            # just iterate through the elements of the array comparing each one:
            for ($i = 0; $i -lt $expected.Count; $i = $i + 1) {
                if ( !(Confirm-Equality $expected.Get($i) $got.Get($i)) ) {
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
            }

            return $true
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
note: >
    I can't wait.
    To get that Cool Book.
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
                comment = "I can't wait. To get that Cool Book."
            }

            $res = ConvertFrom-Yaml $testYaml

            It "Should decode the YAML string as expected." {
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
                Assert-VerifiableMocks
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
                Assert-VerifiableMocks
            }
        }

        Context "Providing a valid -OutFile." {
            $testObject = @{ yes = "No"; "arr" = @(1, 2, 3) }
            $testPath = [System.IO.Path]::GetTempFileName()
            Remove-Item -Force $testPath # must be deleted for the test

            It "Should succesfully write the expected content to the specified -OutFile." {
                $yaml = ConvertTo-Yaml $testObject
                ConvertTo-Yaml $testObject -OutFile $testPath

                Compare-Object $yaml (Get-Content $testPath) | Should Be $true
            }

            # NOTE: the below assertion relies on the above writing its file.
            It "Should succesfully write the expected content to the specified -OutFile with -Force even if it exists." {
                $newTestObject = @(1, "two", @("arr", "ay"), @{ yes = "no"; answer = 42 })

                $yaml = ConvertTo-Yaml  $newTestObject
                ConvertTo-Yaml $newTestObject -OutFile $testPath -Force

                Compare-Object $yaml (Get-Content $testPath) | Should Be $true
            }
        }

    }

}
