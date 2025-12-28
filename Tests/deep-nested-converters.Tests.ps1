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
# Tests for deeply nested structures with custom type converters

BeforeAll {
    Import-Module "$PSScriptRoot/../powershell-yaml.psd1" -Force
    . "$PSScriptRoot/DeepNestedConvertersClasses.ps1"
}

Describe "Deep Nested Custom Converters" {
    Context "Three-level nesting with converters at each level" {
        It "Should deserialize converters at all nesting levels" {
            $yaml = @"
app-name: "ProductionApp"
environment: "prod"
# API Gateway address
api-gateway: !ipaddr "10.0.0.1"
request-timeout: !duration "5h30m0s"
database:
  name: "main_db"
  # Database host address
  host: !ipaddr "192.168.1.100"
  port: 5432
  connection-timeout: !duration "0h1m30s"
  primary-server:
    hostname: "db-primary-01"
    address: !ipaddr "192.168.1.101"
    port: 5432
    timeout: !duration "0h0m30s"
  replica-server:
    hostname: "db-replica-01"
    address: !ipaddr "192.168.1.102"
    port: 5432
    timeout: !duration "0h0m45s"
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])

            # Level 1 converters
            $config.ApiGateway | Should -Not -BeNullOrEmpty
            $config.ApiGateway.ToString() | Should -Be "10.0.0.1"
            $config.ApiGateway.Octet1 | Should -Be 10
            $config.ApiGateway.Octet4 | Should -Be 1

            $config.RequestTimeout | Should -Not -BeNullOrEmpty
            $config.RequestTimeout.ToString() | Should -Be "5h30m0s"
            $config.RequestTimeout.Hours | Should -Be 5
            $config.RequestTimeout.Minutes | Should -Be 30

            # Level 2 converters
            $config.Database.Host.ToString() | Should -Be "192.168.1.100"
            $config.Database.Host.Octet3 | Should -Be 1
            $config.Database.Host.Octet4 | Should -Be 100

            $config.Database.ConnectionTimeout.ToString() | Should -Be "0h1m30s"
            $config.Database.ConnectionTimeout.Minutes | Should -Be 1
            $config.Database.ConnectionTimeout.Seconds | Should -Be 30

            # Level 3 converters (primary server)
            $config.Database.PrimaryServer.Address.ToString() | Should -Be "192.168.1.101"
            $config.Database.PrimaryServer.Address.Octet4 | Should -Be 101

            $config.Database.PrimaryServer.Timeout.ToString() | Should -Be "0h0m30s"
            $config.Database.PrimaryServer.Timeout.Seconds | Should -Be 30

            # Level 3 converters (replica server)
            $config.Database.ReplicaServer.Address.ToString() | Should -Be "192.168.1.102"
            $config.Database.ReplicaServer.Address.Octet4 | Should -Be 102

            $config.Database.ReplicaServer.Timeout.ToString() | Should -Be "0h0m45s"
            $config.Database.ReplicaServer.Timeout.Seconds | Should -Be 45
        }

        It "Should preserve tags at all nesting levels during round-trip" {
            $yaml = @"
app-name: "TestApp"
environment: "test"
api-gateway: !ipaddr "10.1.2.3"
request-timeout: !duration "1h0m0s"
database:
  name: "test_db"
  host: !ipaddr "127.0.0.1"
  port: 3306
  connection-timeout: !duration "0h0m10s"
  primary-server:
    hostname: "localhost"
    address: !ipaddr "127.0.0.1"
    port: 3306
    timeout: !duration "0h0m5s"
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])
            $roundTripped = $config | ConvertTo-Yaml

            # Verify all tags are preserved (note: order may vary)
            $roundTripped | Should -Match "!ipaddr"
            $roundTripped | Should -Match "!duration"
            $roundTripped | Should -Match "10\.1\.2\.3"
            $roundTripped | Should -Match "1h0m0s"
            $roundTripped | Should -Match "127\.0\.0\.1"
            $roundTripped | Should -Match "0h0m10s"
            $roundTripped | Should -Match "0h0m5s"
        }

        It "Should handle dictionary format for nested converters" {
            $yaml = @"
app-name: "DictFormatApp"
environment: "dev"
api-gateway: !ipaddr { a: 172, b: 16, c: 0, d: 1 }
request-timeout: !duration { hours: 2, minutes: 15, seconds: 30 }
database:
  name: "dev_db"
  host: !ipaddr { a: 192, b: 168, c: 1, d: 50 }
  port: 5432
  connection-timeout: !duration { hours: 0, minutes: 2, seconds: 0 }
  primary-server:
    hostname: "dev-primary"
    address: !ipaddr { a: 192, b: 168, c: 1, d: 51 }
    port: 5432
    timeout: !duration { hours: 0, minutes: 0, seconds: 20 }
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])

            # Verify dictionary format was parsed correctly
            $config.ApiGateway.ToString() | Should -Be "172.16.0.1"
            $config.RequestTimeout.Hours | Should -Be 2
            $config.RequestTimeout.Minutes | Should -Be 15
            $config.RequestTimeout.Seconds | Should -Be 30

            $config.Database.Host.ToString() | Should -Be "192.168.1.50"
            $config.Database.ConnectionTimeout.Minutes | Should -Be 2

            $config.Database.PrimaryServer.Address.ToString() | Should -Be "192.168.1.51"
            $config.Database.PrimaryServer.Timeout.Seconds | Should -Be 20
        }

        It "Should handle null nested objects with converters" {
            $yaml = @"
app-name: "MinimalApp"
environment: "test"
api-gateway: !ipaddr "10.0.0.1"
request-timeout: !duration "1h0m0s"
database:
  name: "minimal_db"
  host: !ipaddr "127.0.0.1"
  port: 5432
  connection-timeout: !duration "0h0m30s"
  primary-server: null
  replica-server: null
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])

            $config.ApiGateway | Should -Not -BeNullOrEmpty
            $config.Database | Should -Not -BeNullOrEmpty
            $config.Database.Host | Should -Not -BeNullOrEmpty
            $config.Database.PrimaryServer | Should -BeNullOrEmpty
            $config.Database.ReplicaServer | Should -BeNullOrEmpty
        }

        It "Should preserve comments with nested converters" {
            $yaml = @"
# Main application config
app-name: "CommentedApp"
environment: "prod"
# Gateway IP
api-gateway: !ipaddr "10.0.0.1"
request-timeout: !duration "2h0m0s"
database:
  name: "prod_db"
  # Database IP address
  host: !ipaddr "192.168.1.100"
  port: 5432
  connection-timeout: !duration "0h1m0s"
  primary-server:
    hostname: "primary"
    # Primary server address
    address: !ipaddr "192.168.1.101"
    port: 5432
    # Server timeout
    timeout: !duration "0h0m30s"
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])

            # Verify comments are preserved
            $config.GetPropertyComment('AppName') | Should -Match "Main application config"
            $config.GetPropertyComment('ApiGateway') | Should -Match "Gateway IP"
            $config.Database.GetPropertyComment('Host') | Should -Match "Database IP address"
            $config.Database.PrimaryServer.GetPropertyComment('Address') | Should -Match "Primary server address"
            $config.Database.PrimaryServer.GetPropertyComment('Timeout') | Should -Match "Server timeout"

            # Round-trip and verify comments in output
            $roundTripped = $config | ConvertTo-Yaml

            $roundTripped | Should -Match "# Main application config"
            $roundTripped | Should -Match "# Gateway IP"
            $roundTripped | Should -Match "# Database IP address"
            $roundTripped | Should -Match "# Primary server address"
            $roundTripped | Should -Match "# Server timeout"
        }

        It "Should handle modification of nested converter values" {
            $yaml = @"
app-name: "ModifiableApp"
environment: "dev"
api-gateway: !ipaddr "10.0.0.1"
request-timeout: !duration "1h0m0s"
database:
  name: "dev_db"
  host: !ipaddr "192.168.1.100"
  port: 5432
  connection-timeout: !duration "0h0m30s"
  primary-server:
    hostname: "primary"
    address: !ipaddr "192.168.1.101"
    port: 5432
    timeout: !duration "0h0m15s"
"@

            $config = $yaml | ConvertFrom-Yaml -As ([ApplicationConfig])

            # Modify nested converter values
            $newIp = [CustomIPAddress]@{
                Octet1 = 172
                Octet2 = 16
                Octet3 = 0
                Octet4 = 1
            }
            $config.Database.PrimaryServer.Address = $newIp

            $newTimeout = [Duration]@{
                Hours = 0
                Minutes = 1
                Seconds = 0
            }
            $config.Database.PrimaryServer.Timeout = $newTimeout

            # Serialize and verify
            $roundTripped = $config | ConvertTo-Yaml

            $roundTripped | Should -Match "!ipaddr.*172\.16\.0\.1"
            $roundTripped | Should -Match "!duration.*0h1m0s"
        }

        It "Should handle errors in nested converter parsing" {
            $yaml = @"
app-name: "ErrorApp"
environment: "test"
api-gateway: !ipaddr "not.a.valid.ip"
request-timeout: !duration "1h0m0s"
database:
  name: "test_db"
  host: !ipaddr "127.0.0.1"
  port: 5432
  connection-timeout: !duration "0h0m30s"
"@

            { $yaml | ConvertFrom-Yaml -As ([ApplicationConfig]) } | Should -Throw
        }

        It "Should work with -OmitNull on nested converters" {
            $config = [ApplicationConfig]::new()
            $config.AppName = "NullOmitApp"
            $config.Environment = "test"

            $ip = [CustomIPAddress]@{
                Octet1 = 10
                Octet2 = 0
                Octet3 = 0
                Octet4 = 1
            }
            $config.ApiGateway = $ip

            $duration = [Duration]@{
                Hours = 1
                Minutes = 0
                Seconds = 0
            }
            $config.RequestTimeout = $duration

            # Database is null - should be omitted with -OmitNull
            $yaml = $config | ConvertTo-Yaml -OmitNull

            $yaml | Should -Match "api-gateway: !ipaddr 10\.0\.0\.1"
            $yaml | Should -Match "request-timeout: !duration 1h0m0s"
            $yaml | Should -Not -Match "database:"
        }

        It "Should work with -EmitTags on nested converters" {
            $config = [ApplicationConfig]::new()
            $config.AppName = "TagEmitApp"
            $config.Environment = "prod"

            $ip = [CustomIPAddress]@{
                Octet1 = 192
                Octet2 = 168
                Octet3 = 1
                Octet4 = 1
            }
            $config.ApiGateway = $ip

            $db = [DatabaseConfig]::new()
            $db.Name = "prod_db"
            $db.Port = 5432

            $dbIp = [CustomIPAddress]@{
                Octet1 = 192
                Octet2 = 168
                Octet3 = 1
                Octet4 = 100
            }
            $db.Host = $dbIp

            $config.Database = $db

            $yaml = $config | ConvertTo-Yaml -EmitTags

            # Custom converter tags
            $yaml | Should -Match "api-gateway: !ipaddr 192\.168\.1\.1"
            $yaml | Should -Match "host: !ipaddr 192\.168\.1\.100"

            # Standard tags
            $yaml | Should -Match "app-name: !!str TagEmitApp"
            $yaml | Should -Match "environment: !!str prod"
            $yaml | Should -Match "name: !!str prod_db"
            $yaml | Should -Match "port: !!int 5432"
        }
    }
}
