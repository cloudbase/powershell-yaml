using System;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Property, Inherited = false, AllowMultiple = false)]
public class PowerShellYamlSerializable : Attribute
{
    public bool ShouldRecurse { get; }

    public PowerShellYamlSerializable(bool shouldRecurse)
    {
        ShouldRecurse = shouldRecurse;
    }
}


[AttributeUsage(AttributeTargets.Property, Inherited = false, AllowMultiple = false)]
public class PowerShellYamlPropertyAliasAttribute : Attribute
{
    public string YamlName { get; }

    public PowerShellYamlPropertyAliasAttribute(string yamlName)
    {
        YamlName = yamlName;
    }
}
