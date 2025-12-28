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

using namespace PowerShellYaml

# Test classes for mapping style
class Address : YamlBase {
    [string]$Street = ""
    [string]$City = ""
    [string]$Zip = ""
}

class Person : YamlBase {
    [string]$Name = ""
    [int]$Age = 0
    [Address]$Address = $null
}

class Company : YamlBase {
    [string]$Name = ""
    [Person]$Ceo = $null
    [Person[]]$Employees = @()
}
