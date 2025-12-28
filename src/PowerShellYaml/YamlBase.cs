// Copyright 2016-2026 Cloudbase Solutions Srl
//
//    Licensed under the Apache License, Version 2.0 (the "License"); you may
//    not use this file except in compliance with the License. You may obtain
//    a copy of the License at
//
//         http://www.apache.org/licenses/LICENSE-2.0
//
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
//    License for the specific language governing permissions and limitations
//    under the License.
//

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace PowerShellYaml;

/// <summary>
/// Interface for custom YAML type converters.
/// Implement this interface to provide custom serialization/deserialization for specific YAML tags and types.
/// PowerShell users can create classes with ConvertFromYaml and ConvertToYaml methods that will be called via reflection.
/// </summary>
public interface IYamlTypeConverter
{
    /// <summary>
    /// Determines whether this converter can handle the given tag and target type.
    /// </summary>
    /// <param name="tag">The YAML tag (e.g., "!timestamp", "tag:yaml.org,2002:int"). Null if no tag present.</param>
    /// <param name="targetType">The .NET type the value should be converted to.</param>
    /// <returns>True if this converter can handle the conversion, false otherwise.</returns>
    bool CanHandle(string? tag, Type targetType);

    /// <summary>
    /// Deserialize a YAML value to the target type.
    /// </summary>
    /// <param name="data">The raw value from YAML (string, Dictionary, List, etc.)</param>
    /// <param name="tag">The YAML tag if present, null otherwise.</param>
    /// <param name="targetType">The .NET type to convert to.</param>
    /// <returns>The deserialized object.</returns>
    object? Unmarshal(object? data, string? tag, Type targetType);

    /// <summary>
    /// Serialize an object to YAML representation.
    /// </summary>
    /// <param name="value">The object to serialize.</param>
    /// <param name="tag">Output parameter: the YAML tag to use (e.g., "!timestamp").</param>
    /// <returns>The serialized representation (string, Dictionary, List, etc.).</returns>
    object? Marshal(object? value, out string? tag);
}

/// <summary>
/// Base class for PowerShell-based custom type converters.
/// Inherit from this class in PowerShell and override the abstract methods to create custom converters.
/// </summary>
/// <example>
/// class SemVerConverter : YamlConverter {
///     [bool] CanHandle([string]$tag, [Type]$targetType) {
///         return ($tag -eq '!semver' -or $tag -eq $null) -and $targetType -eq [SemanticVersion]
///     }
///
///     [object] ConvertFromYaml([object]$data, [string]$tag, [Type]$targetType) {
///         # Parse $data and return object
///         return [SemanticVersion]::new()
///     }
///
///     [hashtable] ConvertToYaml([object]$value) {
///         return @{ Value = $value.ToString(); Tag = '!semver' }
///     }
/// }
/// </example>
public abstract class YamlConverter : IYamlTypeConverter
{
    /// <summary>
    /// Determines whether this converter can handle the given tag and target type.
    /// Override this method to implement custom tag/type checking logic.
    /// Default implementation returns true for all inputs.
    /// </summary>
    public virtual bool CanHandle(string? tag, Type targetType)
    {
        return true;
    }

    /// <summary>
    /// Deserialize a YAML value to the target type.
    /// This is an abstract method that must be overridden in PowerShell.
    /// </summary>
    public abstract object? ConvertFromYaml(object? data, string? tag, Type targetType);

    /// <summary>
    /// Serialize an object to YAML representation.
    /// This is an abstract method that must be overridden in PowerShell.
    /// Return a hashtable with 'Value' and 'Tag' keys, or just the value directly.
    /// </summary>
    public abstract object? ConvertToYaml(object? value);

    // IYamlTypeConverter interface implementation
    object? IYamlTypeConverter.Unmarshal(object? data, string? tag, Type targetType)
    {
        return ConvertFromYaml(data, tag, targetType);
    }

    object? IYamlTypeConverter.Marshal(object? value, out string? tag)
    {
        var result = ConvertToYaml(value);

        // Handle Dictionary<string, object?>
        if (result is Dictionary<string, object?> dict)
        {
            tag = dict.TryGetValue("Tag", out var tagValue) ? tagValue as string : null;
            return dict.TryGetValue("Value", out var valueResult) ? valueResult : null;
        }

        // Handle PowerShell Hashtable
        if (result is IDictionary hashtable)
        {
            tag = hashtable.Contains("Tag") ? hashtable["Tag"] as string : null;
            return hashtable.Contains("Value") ? hashtable["Value"] : null;
        }

        // Fallback: treat result as the value, no tag
        tag = null;
        return result;
    }
}

/// <summary>
/// Attribute to specify a custom YAML type converter for a property.
/// Use this to control how a property is serialized/deserialized to/from YAML.
/// </summary>
/// <example>
/// class TimestampConverter : IYamlTypeConverter {
///     // Implementation...
/// }
///
/// class MyClass : YamlBase {
///     [YamlConverter(typeof(TimestampConverter))]
///     [DateTime]$CreatedAt
/// }
/// </example>
[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class YamlConverterAttribute : Attribute
{
    public Type? ConverterType { get; }
    public string? ConverterTypeName { get; }

    // Constructor for C# usage with Type
    public YamlConverterAttribute(Type converterType)
    {
        if (!typeof(IYamlTypeConverter).IsAssignableFrom(converterType))
        {
            throw new ArgumentException(
                $"Type '{converterType.FullName}' must implement IYamlTypeConverter interface.",
                nameof(converterType));
        }
        ConverterType = converterType;
    }

    // Constructor for PowerShell usage with type name string (avoids ALC issues)
    public YamlConverterAttribute(string converterTypeName)
    {
        ConverterTypeName = converterTypeName;
    }
}

/// <summary>
/// Attribute to specify the YAML key name for a property.
/// Use this when you need to map a YAML key to a property with a different name.
/// This is especially useful for case-sensitive YAML keys since PowerShell class properties are case-insensitive.
/// </summary>
/// <example>
/// class MyClass : YamlBase {
///     [YamlKey("Test")]
///     [string]$CapitalizedTest
///
///     [YamlKey("test")]
///     [int]$LowercaseTest
/// }
/// </example>
[AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
public class YamlKeyAttribute(string key) : Attribute
{
    public string Key { get; } = key;
}

/// <summary>
/// Base class for typed YAML objects that users can inherit from in PowerShell.
/// This class is loaded into the Default ALC, making it available for PowerShell class inheritance.
/// Includes metadata storage for YAML comments, styles, tags, etc.
/// </summary>
public abstract class YamlBase
{
    // Metadata storage using only ALC-safe types (Dictionary from mscorlib)
    // Stores: property name -> metadata dictionary (e.g., "comment" -> "comment text")
    private readonly Dictionary<string, Dictionary<string, object?>> _metadata =
        new Dictionary<string, Dictionary<string, object?>>();

    /// <summary>
    /// Convert this object to a dictionary for YAML serialization.
    /// Override this method to provide custom serialization logic.
    /// Default implementation uses reflection to serialize all public properties.
    /// </summary>
    public virtual Dictionary<string, object?> ToDictionary()
    {
        var dict = new Dictionary<string, object?>();
        var type = GetType();
        var properties = type.GetProperties(BindingFlags.Public | BindingFlags.Instance);

        foreach (var prop in properties)
        {
            // Skip metadata property
            if (prop.Name == "_metadata" || prop.Name == "EqualityContract")
                continue;

            var value = prop.GetValue(this);
            var key = GetYamlKeyForProperty(prop);

            // Check for custom converter attribute using GetCustomAttributesData to avoid ALC issues
            var converterType = GetConverterTypeFromProperty(prop);
            if (converterType != null && value != null)
            {
                try
                {
                    var converter = (IYamlTypeConverter?)Activator.CreateInstance(converterType);
                    if (converter == null)
                    {
                        throw new InvalidOperationException(
                            $"Failed to create instance of converter type '{converterType.FullName}'");
                    }

                    // Use custom converter to marshal the value
                    string? tag;
                    var marshaledValue = converter.Marshal(value, out tag);

                    // Store the tag in metadata if provided
                    if (!string.IsNullOrEmpty(tag))
                    {
                        SetPropertyTag(prop.Name, tag);
                    }

                    dict[key] = marshaledValue;
                    continue;
                }
                catch (Exception ex) when (!(ex is InvalidOperationException))
                {
                    throw new InvalidOperationException(
                        $"Custom converter '{converterType.Name}' failed to serialize property '{prop.Name}' " +
                        $"with value '{value}'. See inner exception for details.", ex);
                }
            }

            // Keep YamlBase references for metadata preservation
            // Arrays are kept as-is (they'll be handled by serializer)
            dict[key] = value;
        }

        return dict;
    }

    /// <summary>
    /// Populate this object from a dictionary after YAML deserialization.
    /// Override this method to provide custom deserialization logic.
    /// Default implementation uses reflection to populate all public properties.
    /// </summary>
    public virtual void FromDictionary(Dictionary<string, object?> data)
    {
        var type = GetType();
        var properties = type.GetProperties(BindingFlags.Public | BindingFlags.Instance);

        foreach (var prop in properties)
        {
            // Skip metadata property
            if (prop.Name == "_metadata" || prop.Name == "EqualityContract")
                continue;

            if (!prop.CanWrite)
                continue;

            var yamlKey = GetYamlKeyForProperty(prop);
            if (!data.ContainsKey(yamlKey))
                continue;

            var value = data[yamlKey];
            if (value == null)
            {
                prop.SetValue(this, null);
                continue;
            }

            // Check for custom converter attribute using GetCustomAttributesData to avoid ALC issues
            var converterType = GetConverterTypeFromProperty(prop);
            if (converterType != null)
            {
                try
                {
                    var converter = (IYamlTypeConverter?)Activator.CreateInstance(converterType);
                    if (converter == null)
                    {
                        throw new InvalidOperationException(
                            $"Failed to create instance of converter type '{converterType.FullName}'");
                    }

                    // Get the tag from metadata if available
                    string? tag = null;
                    if (_metadata.TryGetValue(prop.Name, out var propMeta))
                    {
                        if (propMeta.TryGetValue("tag", out var tagValue))
                        {
                            tag = tagValue as string;
                        }
                    }

                    // Check if converter can handle this
                    if (!converter.CanHandle(tag, prop.PropertyType))
                    {
                        throw new InvalidOperationException(
                            $"Custom converter '{converterType.Name}' registered for property '{prop.Name}' " +
                            $"cannot handle tag '{tag ?? "(none)"}' with target type '{prop.PropertyType.Name}'. " +
                            $"The converter's CanHandle() method returned false.");
                    }

                    // Use custom converter
                    var convertedValue = converter.Unmarshal(value, tag, prop.PropertyType);
                    prop.SetValue(this, convertedValue);
                    continue;
                }
                catch (Exception ex) when (ex is not InvalidOperationException)
                {
                    throw new InvalidOperationException(
                        $"Custom converter '{converterType.Name}' failed to deserialize property '{prop.Name}' " +
                        $"with value '{value}'. See inner exception for details.", ex);
                }
            }

            // Check if value is a nested object (dictionary)
            if (value is Dictionary<string, object?> nestedDict)
            {
                // Handle nested YamlBase objects
                if (typeof(YamlBase).IsAssignableFrom(prop.PropertyType))
                {
                    var nestedInstance = (YamlBase?)Activator.CreateInstance(prop.PropertyType);
                    if (nestedInstance != null)
                    {
                        nestedInstance.FromDictionary(nestedDict);
                        prop.SetValue(this, nestedInstance);
                    }
                    continue;
                }
                // Detect non-YamlBase class types that can't be deserialized
                else if (prop.PropertyType.IsClass &&
                         prop.PropertyType != typeof(string) &&
                         !prop.PropertyType.IsPrimitive)
                {
                    throw new InvalidOperationException(
                        $"Property '{prop.Name}' of type '{prop.PropertyType.Name}' in class '{type.Name}' must inherit from YamlBase " +
                        $"for nested object deserialization. Custom classes that don't inherit from YamlBase cannot be automatically deserialized from YAML. " +
                        $"Either make '{prop.PropertyType.Name}' inherit from YamlBase, or use a primitive type or PSCustomObject.");
                }
            }

            // Handle arrays
            if (prop.PropertyType.IsArray && value is IList list)
            {
                var elementType = prop.PropertyType.GetElementType();
                if (elementType != null)
                {
                    // Handle arrays of YamlBase objects
                    if (typeof(YamlBase).IsAssignableFrom(elementType))
                    {
                        var array = Array.CreateInstance(elementType, list.Count);
                        for (int i = 0; i < list.Count; i++)
                        {
                            if (list[i] is Dictionary<string, object?> itemDict)
                            {
                                var item = (YamlBase?)Activator.CreateInstance(elementType);
                                if (item != null)
                                {
                                    item.FromDictionary(itemDict);
                                    array.SetValue(item, i);
                                }
                            }
                        }
                        prop.SetValue(this, array);
                        continue;
                    }
                    // Detect arrays of non-YamlBase class types
                    else if (elementType.IsClass &&
                             elementType != typeof(string) &&
                             !elementType.IsPrimitive &&
                             list.Count > 0 &&
                             list[0] is Dictionary<string, object?>)
                    {
                        throw new InvalidOperationException(
                            $"Property '{prop.Name}' is an array of type '{elementType.Name}[]' in class '{type.Name}', " +
                            $"but '{elementType.Name}' does not inherit from YamlBase. " +
                            $"Custom class arrays must use types that inherit from YamlBase for deserialization. " +
                            $"Either make '{elementType.Name}' inherit from YamlBase, or use a primitive type array.");
                    }
                    // Handle arrays of primitive types (string[], int[], etc.)
                    else
                    {
                        var array = Array.CreateInstance(elementType, list.Count);
                        for (int i = 0; i < list.Count; i++)
                        {
                            var item = list[i];
                            if (item != null)
                            {
                                try
                                {
                                    var convertedItem = Convert.ChangeType(item, elementType);
                                    array.SetValue(convertedItem, i);
                                }
                                catch
                                {
                                    array.SetValue(item, i);
                                }
                            }
                        }
                        prop.SetValue(this, array);
                        continue;
                    }
                }
            }

            // Handle direct value assignment with type conversion
            try
            {
                var convertedValue = Convert.ChangeType(value, prop.PropertyType);
                prop.SetValue(this, convertedValue);
            }
            catch
            {
                // If conversion fails, try direct assignment
                prop.SetValue(this, value);
            }
        }
    }

    /// <summary>
    /// Get the converter type from a property's YamlConverterAttribute without instantiating the attribute.
    /// Uses GetCustomAttributesData to avoid ALC issues with PowerShell classes.
    /// </summary>
    private static Type? GetConverterTypeFromProperty(PropertyInfo prop)
    {
        foreach (var attrData in prop.GetCustomAttributesData())
        {
            if (attrData.AttributeType == typeof(YamlConverterAttribute))
            {
                // Get the constructor argument
                if (attrData.ConstructorArguments.Count > 0)
                {
                    var arg = attrData.ConstructorArguments[0];

                    // If it's a Type, validate and return it
                    if (arg.Value is Type type)
                    {
                        ValidateConverterType(type);
                        return type;
                    }

                    // If it's a string type name, resolve it from the declaring type's assembly
                    if (arg.Value is string typeName)
                    {
                        return ResolveConverterType(typeName, prop.DeclaringType);
                    }
                }
            }
        }
        return null;
    }

    /// <summary>
    /// Resolve a converter type by name, searching only in the declaring type's assembly.
    /// This ensures that user-defined converters in the same script/module always take precedence.
    /// </summary>
    private static Type ResolveConverterType(string typeName, Type? declaringType)
    {
        if (declaringType?.Assembly == null)
        {
            throw new InvalidOperationException(
                $"Cannot resolve converter type '{typeName}' - declaring type has no assembly");
        }

        // For PowerShell classes: all classes in the same script/module share the same
        // dynamic "PowerShell Class Assembly", so this will find converters defined alongside the class
        Type? resolvedType;
        try
        {
            resolvedType = declaringType.Assembly.GetType(typeName);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"Error resolving converter type '{typeName}' in assembly '{declaringType.Assembly.FullName}'",
                ex);
        }

        if (resolvedType == null)
        {
            throw new InvalidOperationException(
                $"Converter type '{typeName}' not found. " +
                $"Make sure it's defined in the same file/module as your class.");
        }

        ValidateConverterType(resolvedType);
        return resolvedType;
    }

    /// <summary>
    /// Validate that a type implements IYamlTypeConverter interface.
    /// </summary>
    private static void ValidateConverterType(Type type)
    {
        if (!typeof(IYamlTypeConverter).IsAssignableFrom(type))
        {
            throw new ArgumentException(
                $"Type '{type.FullName}' must implement IYamlTypeConverter interface",
                nameof(type));
        }
    }

    /// <summary>
    /// Get the YAML key for a property, checking for YamlKeyAttribute first.
    /// </summary>
    private static string GetYamlKeyForProperty(PropertyInfo prop)
    {
        // Check if property has YamlKeyAttribute
        var yamlKeyAttr = prop.GetCustomAttribute<YamlKeyAttribute>();
        if (yamlKeyAttr != null)
        {
            return yamlKeyAttr.Key;
        }

        // Fall back to automatic conversion
        return ConvertPropertyNameToYamlKey(prop.Name);
    }

    private static string ConvertPropertyNameToYamlKey(string propertyName)
    {
        // Convert PascalCase to hyphenated-case
        // Example: AppName -> app-name, DatabaseHost -> database-host
        var result = new System.Text.StringBuilder();
        for (int i = 0; i < propertyName.Length; i++)
        {
            char c = propertyName[i];
            if (char.IsUpper(c))
            {
                if (i > 0)
                {
                    result.Append('-');
                }
                result.Append(char.ToLower(c));
            }
            else
            {
                result.Append(c);
            }
        }
        return result.ToString();
    }

    // Metadata access methods - use string keys to avoid ALC type identity issues

    public void SetPropertyComment(string propertyName, string? comment)
    {
        GetOrCreateMetadata(propertyName)["comment"] = comment;
    }

    public string? GetPropertyComment(string propertyName)
    {
        return GetMetadataValue(propertyName, "comment") as string;
    }

    public void SetPropertyScalarStyle(string propertyName, string? style)
    {
        GetOrCreateMetadata(propertyName)["scalarStyle"] = style;
    }

    public string? GetPropertyScalarStyle(string propertyName)
    {
        return GetMetadataValue(propertyName, "scalarStyle") as string;
    }

    public void SetPropertyMappingStyle(string propertyName, string? style)
    {
        GetOrCreateMetadata(propertyName)["mappingStyle"] = style;
    }

    public string? GetPropertyMappingStyle(string propertyName)
    {
        return GetMetadataValue(propertyName, "mappingStyle") as string;
    }

    /// <summary>
    /// Set the mapping style for this document/object itself (not a property).
    /// Used to preserve flow vs block style at the root level.
    /// </summary>
    public void SetDocumentMappingStyle(string? style)
    {
        GetOrCreateMetadata("")["mappingStyle"] = style;
    }

    /// <summary>
    /// Get the mapping style for this document/object itself (not a property).
    /// </summary>
    public string? GetDocumentMappingStyle()
    {
        return GetMetadataValue("", "mappingStyle") as string;
    }

    public void SetPropertySequenceStyle(string propertyName, string? style)
    {
        GetOrCreateMetadata(propertyName)["sequenceStyle"] = style;
    }

    public string? GetPropertySequenceStyle(string propertyName)
    {
        return GetMetadataValue(propertyName, "sequenceStyle") as string;
    }

    public void SetPropertyTag(string propertyName, string? tag)
    {
        GetOrCreateMetadata(propertyName)["tag"] = tag;
    }

    public string? GetPropertyTag(string propertyName)
    {
        return GetMetadataValue(propertyName, "tag") as string;
    }

    /// <summary>
    /// Get the full metadata dictionary for a property (for internal use by cmdlets)
    /// </summary>
    public Dictionary<string, object?>? GetPropertyMetadata(string propertyName)
    {
        return _metadata.TryGetValue(propertyName, out var meta) ? meta : null;
    }

    /// <summary>
    /// Set the full metadata dictionary for a property (for internal use by cmdlets)
    /// </summary>
    public void SetPropertyMetadata(string propertyName, Dictionary<string, object?> metadata)
    {
        _metadata[propertyName] = metadata;
    }

    /// <summary>
    /// Get all metadata for serialization
    /// </summary>
    public Dictionary<string, Dictionary<string, object?>> GetAllMetadata()
    {
        return _metadata;
    }

    private Dictionary<string, object?> GetOrCreateMetadata(string propertyName)
    {
        if (!_metadata.TryGetValue(propertyName, out var meta))
        {
            meta = new Dictionary<string, object?>();
            _metadata[propertyName] = meta;
        }
        return meta;
    }

    private object? GetMetadataValue(string propertyName, string key)
    {
        if (_metadata.TryGetValue(propertyName, out var meta))
        {
            return meta.TryGetValue(key, out var value) ? value : null;
        }
        return null;
    }
}
