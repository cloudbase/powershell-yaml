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
using YamlDotNet.Core;
using YamlDotNet.Core.Events;

namespace PowerShellYaml.Module;

/// <summary>
/// Public API for typed YAML conversion.
/// Provides static methods for serializing and deserializing YamlBase objects.
/// </summary>
public static class TypedYamlConverter
{
    #region Deserialization (YAML to Object)

    /// <summary>
    /// Deserialize YAML string to a typed object inheriting from YamlBase.
    /// </summary>
    public static object? FromYaml(string yaml, Type targetType)
    {
        // Validate that the type inherits from YamlBase
        if (targetType is null || !typeof(YamlBase).IsAssignableFrom(targetType))
        {
            throw new ArgumentException($"Type must inherit from PowerShellYaml.YamlBase", nameof(targetType));
        }

        // Parse YAML with metadata preservation (allow duplicate keys for typed mode)
        var (data, metadata) = YamlDocumentParser.ParseWithMetadata(yaml, allowDuplicateKeys: true);

        // Convert to Dictionary<string, object?> for FromDictionary
        var dict = ConvertToStringKeyDictionary(data);

        // Validate that case-insensitive duplicate YAML keys have explicit mappings in the type
        ValidateDuplicateKeysHaveExplicitMappings(dict, targetType);

        // Create an instance of the user's PowerShell class
        var instance = (YamlBase?)Activator.CreateInstance(targetType);
        if (instance is null)
        {
            throw new InvalidOperationException($"Failed to create instance of type {targetType.FullName}");
        }

        // Copy top-level metadata BEFORE calling FromDictionary
        // This ensures custom converters can access tags during deserialization
        if (metadata != null)
        {
            CopyTopLevelMetadataToYamlBase(instance, metadata);

            // Copy document-level mapping style if present
            if (metadata.DocumentMappingStyle.HasValue)
            {
                instance.SetDocumentMappingStyle(metadata.DocumentMappingStyle.Value.ToString());
            }
        }

        // Populate the instance using the abstract method
        instance.FromDictionary(dict);

        // Copy nested object metadata AFTER FromDictionary has created the nested objects
        if (metadata != null)
        {
            CopyNestedMetadataToYamlBase(instance, metadata, "");
        }

        return instance;
    }

    public static Dictionary<string, object?> ConvertToStringKeyDictionary(object? obj)
    {
        if (obj is null)
            return new Dictionary<string, object?>();

        if (obj is IDictionary dict)
        {
            var result = new Dictionary<string, object?>();
            foreach (DictionaryEntry entry in dict)
            {
                var key = entry.Key?.ToString() ?? string.Empty;
                var value = ConvertValue(entry.Value);
                result[key] = value;
            }
            return result;
        }

        throw new InvalidOperationException("YAML root must be a mapping");
    }

    private static object? ConvertValue(object? value)
    {
        if (value is null)
            return null;

        // Recursively convert nested dictionaries
        if (value is IDictionary dict)
        {
            var result = new Dictionary<string, object?>();
            foreach (DictionaryEntry entry in dict)
            {
                var key = entry.Key?.ToString() ?? string.Empty;
                result[key] = ConvertValue(entry.Value);
            }
            return result;
        }

        // Convert lists
        if (value is IList list)
        {
            var result = new List<object?>();
            foreach (var item in list)
            {
                result.Add(ConvertValue(item));
            }
            return result;
        }

        return value;
    }

    /// <summary>
    /// Copy top-level property metadata (tags, comments, styles) to YamlBase instance.
    /// This must be called BEFORE FromDictionary so custom converters can access tags.
    /// </summary>
    public static void CopyTopLevelMetadataToYamlBase(YamlBase instance, YamlMetadataStore metadataStore)
    {
        var properties = instance.GetType().GetProperties();

        foreach (var prop in properties)
        {
            var propName = prop.Name;
            var yamlKey = GetYamlKeyForProperty(prop);

            // Copy all metadata for this property
            var comment = metadataStore.GetPropertyComment(yamlKey);
            if (!string.IsNullOrEmpty(comment))
            {
                instance.SetPropertyComment(propName, comment);
            }

            var scalarStyle = metadataStore.GetPropertyScalarStyle(yamlKey);
            if (scalarStyle.HasValue)
            {
                instance.SetPropertyScalarStyle(propName, scalarStyle.Value.ToString());
            }

            var mappingStyle = metadataStore.GetPropertyMappingStyle(yamlKey);
            if (mappingStyle.HasValue)
            {
                instance.SetPropertyMappingStyle(propName, mappingStyle.Value.ToString());
            }

            var sequenceStyle = metadataStore.GetPropertySequenceStyle(yamlKey);
            if (sequenceStyle.HasValue)
            {
                instance.SetPropertySequenceStyle(propName, sequenceStyle.Value.ToString());
            }

            var tag = metadataStore.GetPropertyTag(yamlKey);
            if (!string.IsNullOrEmpty(tag))
            {
                instance.SetPropertyTag(propName, tag);
            }
        }
    }

    /// <summary>
    /// Copy nested object metadata to YamlBase instance.
    /// This must be called AFTER FromDictionary so nested objects exist.
    /// </summary>
    public static void CopyNestedMetadataToYamlBase(YamlBase instance, YamlMetadataStore metadataStore, string pathPrefix)
    {
        var properties = instance.GetType().GetProperties();

        foreach (var prop in properties)
        {
            var yamlKey = GetYamlKeyForProperty(prop);
            var propValue = prop.GetValue(instance);

            // Handle nested YamlBase objects
            if (propValue is YamlBase nestedYamlBase)
            {
                var nestedMetadata = metadataStore.GetNestedMetadata(yamlKey);
                if (nestedMetadata != null)
                {
                    // Copy top-level metadata for the nested object first
                    CopyTopLevelMetadataToYamlBase(nestedYamlBase, nestedMetadata);
                    // Then recursively copy its nested metadata
                    CopyNestedMetadataToYamlBase(nestedYamlBase, nestedMetadata, $"{pathPrefix}{yamlKey}.");
                }
            }
            // Handle arrays of YamlBase objects
            else if (propValue is Array array)
            {
                var arrayPropertyMetadata = metadataStore.GetNestedMetadata(yamlKey);
                if (arrayPropertyMetadata != null)
                {
                    for (int i = 0; i < array.Length; i++)
                    {
                        if (array.GetValue(i) is YamlBase arrayItem)
                        {
                            var itemMetadata = arrayPropertyMetadata.GetNestedMetadata($"[{i}]");
                            if (itemMetadata != null)
                            {
                                CopyTopLevelMetadataToYamlBase(arrayItem, itemMetadata);
                                CopyNestedMetadataToYamlBase(arrayItem, itemMetadata, $"{pathPrefix}{yamlKey}[{i}].");
                            }
                        }
                    }
                }
            }
        }
    }

    /// <summary>
    /// Validate that case-insensitive duplicate YAML keys have explicit [YamlKey] mappings.
    /// This prevents silent data loss when YAML contains keys like "test" and "Test".
    /// </summary>
    internal static void ValidateDuplicateKeysHaveExplicitMappings(Dictionary<string, object?> dict, Type targetType)
    {
        // First, check if the YAML dictionary has case-insensitive duplicate keys
        var yamlKeysGrouped = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

        foreach (var yamlKey in dict.Keys)
        {
            if (!yamlKeysGrouped.ContainsKey(yamlKey))
            {
                yamlKeysGrouped[yamlKey] = new List<string>();
            }
            yamlKeysGrouped[yamlKey].Add(yamlKey);
        }

        // Find groups with multiple case variations
        foreach (var kvp in yamlKeysGrouped)
        {
            if (kvp.Value.Count > 1)
            {
                // We have case-insensitive duplicates (e.g., "test" and "Test")
                // Now verify that ALL of these variations are explicitly mapped using [YamlKey]
                var properties = targetType.GetProperties();
                var explicitlyMapped = new HashSet<string>();

                foreach (var prop in properties)
                {
                    var yamlKeyAttr = prop.GetCustomAttribute<YamlKeyAttribute>();
                    if (yamlKeyAttr != null)
                    {
                        // This property has an explicit YamlKey attribute
                        explicitlyMapped.Add(yamlKeyAttr.Key);
                    }
                }

                // Check if all case variations are explicitly mapped
                var unmappedKeys = new List<string>();
                foreach (var yamlKey in kvp.Value)
                {
                    if (!explicitlyMapped.Contains(yamlKey))
                    {
                        unmappedKeys.Add(yamlKey);
                    }
                }

                if (unmappedKeys.Count > 0)
                {
                    throw new InvalidOperationException(
                        $"YAML contains case-insensitive duplicate keys: {string.Join(", ", kvp.Value)}. " +
                        $"To prevent data loss, all variations must be explicitly mapped using [YamlKey] attributes. " +
                        $"Unmapped keys: {string.Join(", ", unmappedKeys)}");
                }
            }
        }
    }

    #endregion

    #region Serialization (Object to YAML)

    /// <summary>
    /// Serialize a YamlBase object to YAML string.
    /// </summary>
    public static string ToYaml(YamlBase obj, bool omitNull = false, bool emitTags = false, bool useFlowStyle = false, bool useBlockStyle = false, bool useSequenceFlowStyle = false, bool useSequenceBlockStyle = false, bool indentedSequences = false, int maxDepth = 100)
    {
        if (obj is null)
        {
            throw new ArgumentNullException(nameof(obj));
        }

        // Convert boolean flags to nullable style overrides
        MappingStyle? mappingStyleOverride = null;
        if (useBlockStyle)
        {
            mappingStyleOverride = MappingStyle.Block;
        }
        else if (useFlowStyle)
        {
            mappingStyleOverride = MappingStyle.Flow;
        }

        SequenceStyle? sequenceStyleOverride = null;
        if (useSequenceBlockStyle)
        {
            sequenceStyleOverride = SequenceStyle.Block;
        }
        else if (useSequenceFlowStyle)
        {
            sequenceStyleOverride = SequenceStyle.Flow;
        }

        return SerializeWithMetadata(obj, emitTags, omitNull, mappingStyleOverride, sequenceStyleOverride, indentedSequences, maxDepth);
    }

    public static string SerializeWithMetadata(YamlBase obj, bool emitTags, bool omitNull, MappingStyle? mappingStyleOverride, SequenceStyle? sequenceStyleOverride, bool indentedSequences = false, int maxDepth = 100)
    {
        var stringWriter = new StringWriter();

        // Create emitter with or without indented sequences
        IEmitter emitter;
        if (indentedSequences)
        {
            // EmitterSettings constructor signature (from YamlDotNet):
            // EmitterSettings(int bestIndent, int bestWidth, bool isCanonical, int maxSimpleKeyLength, bool skipAnchorName, bool indentSequences, string? newLine, bool forceIndentLess)
            // Use default values for most parameters, only set indentSequences to true
            var emitterSettings = new EmitterSettings(
                bestIndent: 2,
                bestWidth: int.MaxValue,
                isCanonical: false,
                maxSimpleKeyLength: 1024,
                skipAnchorName: false,
                indentSequences: true
            );
            emitter = new Emitter(stringWriter, emitterSettings);
        }
        else
        {
            emitter = new Emitter(stringWriter);
        }

        emitter.Emit(new StreamStart());
        emitter.Emit(new DocumentStart());

        SerializeObject(obj, emitter, emitTags, omitNull, mappingStyleOverride, sequenceStyleOverride, 0, maxDepth);

        emitter.Emit(new DocumentEnd(true)); // true = implicit (no "..." marker)
        emitter.Emit(new StreamEnd());

        return stringWriter.ToString();
    }

    private static void SerializeObject(YamlBase obj, IEmitter emitter, bool emitTags, bool omitNull, MappingStyle? mappingStyleOverride, SequenceStyle? sequenceStyleOverride, int currentDepth, int maxDepth)
    {
        if (currentDepth >= maxDepth)
        {
            // Emit a placeholder string to indicate max depth reached
            emitter.Emit(new Scalar("..."));
            return;
        }

        // Determine mapping style with precedence:
        // 1. mappingStyleOverride (if set by user)
        // 2. Object metadata (document-level mapping style)
        // 3. Default to block
        MappingStyle mappingStyle;
        if (mappingStyleOverride.HasValue)
        {
            mappingStyle = mappingStyleOverride.Value;
        }
        else
        {
            // Check if the object has a document-level mapping style
            var documentStyleStr = obj.GetDocumentMappingStyle();
            mappingStyle = documentStyleStr == "Flow" ? MappingStyle.Flow : MappingStyle.Block;
        }
        SerializeObjectWithStyle(obj, emitter, emitTags, omitNull, mappingStyle, mappingStyleOverride, sequenceStyleOverride, currentDepth, maxDepth);
    }

    private static void SerializeObjectWithStyle(YamlBase obj, IEmitter emitter, bool emitTags, bool omitNull, MappingStyle mappingStyle, MappingStyle? mappingStyleOverride, SequenceStyle? sequenceStyleOverride, int currentDepth, int maxDepth)
    {
        var dict = obj.ToDictionary();
        var metadata = obj.GetAllMetadata();
        var type = obj.GetType();
        var properties = type.GetProperties(BindingFlags.Public | BindingFlags.Instance);

        emitter.Emit(new MappingStart(null, null, false, mappingStyle));

        // Iterate through properties to preserve order and get correct YAML keys
        foreach (var prop in properties)
        {
            if (prop.Name == "EqualityContract") continue;

            var propName = prop.Name;
            var yamlKey = GetYamlKeyForProperty(prop);

            // Get value from dictionary
            if (!dict.TryGetValue(yamlKey, out var value))
            {
                continue;
            }

            // Skip null values if OmitNull is enabled
            if (omitNull && value is null)
            {
                continue;
            }

            // Emit comment if present
            if (metadata.TryGetValue(propName, out var propMetadata))
            {
                if (propMetadata.TryGetValue("comment", out var commentObj) && commentObj is string comment && !string.IsNullOrEmpty(comment))
                {
                    emitter.Emit(new Comment(comment, false));
                }
            }

            // Emit key
            emitter.Emit(new Scalar(yamlKey));

            // Emit value with metadata
            EmitValue(value, emitter, obj, propName, emitTags, omitNull, mappingStyleOverride, sequenceStyleOverride, currentDepth, maxDepth);
        }

        emitter.Emit(new MappingEnd());
    }

    private static void EmitValue(object? value, IEmitter emitter, YamlBase? parentObj, string? propertyName, bool emitTags, bool omitNull, MappingStyle? mappingStyleOverride, SequenceStyle? sequenceStyleOverride, int currentDepth, int maxDepth)
    {
        if (value is null)
        {
            var nullTag = emitTags ? new TagName("tag:yaml.org,2002:null") : TagName.Empty;
            emitter.Emit(new Scalar(AnchorName.Empty, nullTag, "null", ScalarStyle.Plain, !emitTags, false));
            return;
        }

        // Check depth limit for nested structures
        if (currentDepth >= maxDepth)
        {
            emitter.Emit(new Scalar("..."));
            return;
        }

        // Handle nested YamlBase objects
        if (value is YamlBase nestedYaml)
        {
            // Determine mapping style with precedence:
            // 1. mappingStyleOverride (if set by user)
            // 2. Parent's property metadata (property-level mapping style)
            // 3. Default to block
            MappingStyle mappingStyle;
            if (mappingStyleOverride.HasValue)
            {
                mappingStyle = mappingStyleOverride.Value;
            }
            else if (parentObj != null && propertyName != null)
            {
                var styleStr = parentObj.GetPropertyMappingStyle(propertyName);
                mappingStyle = styleStr == "Flow" ? MappingStyle.Flow : MappingStyle.Block;
            }
            else
            {
                mappingStyle = MappingStyle.Block;
            }

            SerializeObjectWithStyle(nestedYaml, emitter, emitTags, omitNull, mappingStyle, mappingStyleOverride, sequenceStyleOverride, currentDepth + 1, maxDepth);
            return;
        }

        // Handle dictionaries (from nested objects)
        if (value is Dictionary<string, object?> dict)
        {
            // Determine mapping style with same precedence as nested YamlBase
            MappingStyle mappingStyle;
            if (mappingStyleOverride.HasValue)
            {
                mappingStyle = mappingStyleOverride.Value;
            }
            else if (parentObj != null && propertyName != null)
            {
                var styleStr = parentObj.GetPropertyMappingStyle(propertyName);
                mappingStyle = styleStr == "Flow" ? MappingStyle.Flow : MappingStyle.Block;
            }
            else
            {
                mappingStyle = MappingStyle.Block;
            }

            emitter.Emit(new MappingStart(null, null, false, mappingStyle));
            foreach (var kvp in dict)
            {
                // Skip null values in dictionaries if OmitNull is enabled
                if (omitNull && kvp.Value is null)
                {
                    continue;
                }

                emitter.Emit(new Scalar(kvp.Key));
                EmitValue(kvp.Value, emitter, null, null, emitTags, omitNull, mappingStyleOverride, sequenceStyleOverride, currentDepth + 1, maxDepth);
            }
            emitter.Emit(new MappingEnd());
            return;
        }

        // Handle lists/arrays
        if (value is IList list)
        {
            // Determine sequence style with precedence:
            // 1. sequenceStyleOverride (if set by user)
            // 2. Parent's property metadata (property-level sequence style)
            // 3. Default to block
            SequenceStyle seqStyle;
            if (sequenceStyleOverride.HasValue)
            {
                seqStyle = sequenceStyleOverride.Value;
            }
            else if (parentObj != null && propertyName != null)
            {
                var styleStr = parentObj.GetPropertySequenceStyle(propertyName);
                seqStyle = styleStr == "Flow" ? SequenceStyle.Flow : SequenceStyle.Block;
            }
            else
            {
                seqStyle = SequenceStyle.Block;
            }

            emitter.Emit(new SequenceStart(null, null, false, seqStyle));
            foreach (var item in list)
            {
                // Note: We don't skip null items in arrays - preserve array structure
                EmitValue(item, emitter, null, null, emitTags, omitNull, mappingStyleOverride, sequenceStyleOverride, currentDepth + 1, maxDepth);
            }
            emitter.Emit(new SequenceEnd());
            return;
        }

        // Emit scalar value with style and tag from metadata
        var scalarStyle = ScalarStyle.Any;
        var tag = TagName.Empty;

        if (parentObj != null && propertyName != null)
        {
            // Get scalar style from metadata
            var styleStr = parentObj.GetPropertyScalarStyle(propertyName);
            if (!string.IsNullOrEmpty(styleStr))
            {
                scalarStyle = styleStr switch
                {
                    "DoubleQuoted" => ScalarStyle.DoubleQuoted,
                    "SingleQuoted" => ScalarStyle.SingleQuoted,
                    "Literal" => ScalarStyle.Literal,
                    "Folded" => ScalarStyle.Folded,
                    "Plain" => ScalarStyle.Plain,
                    _ => ScalarStyle.Any
                };
            }

            // Get tag from metadata (e.g., tag:yaml.org,2002:int)
            var tagStr = parentObj.GetPropertyTag(propertyName);
            if (!string.IsNullOrEmpty(tagStr))
            {
                tag = new TagName(tagStr!);  // tagStr is guaranteed non-null by the check above
            }
        }

        // If emitTags is enabled and no tag from metadata, infer tag from .NET type
        if (emitTags && tag.IsEmpty)
        {
            tag = GetTagFromType(value);
        }

        var valueStr = value.ToString() ?? string.Empty;

        // If we have an explicit tag from metadata or emitTags, force it to be emitted
        // by setting both implicit flags to false
        var isPlainImplicit = tag.IsEmpty;
        var isQuotedImplicit = tag.IsEmpty;

        emitter.Emit(new Scalar(AnchorName.Empty, tag, valueStr, scalarStyle, isPlainImplicit, isQuotedImplicit));
    }

    private static TagName GetTagFromType(object value)
    {
        return value switch
        {
            int => new TagName("tag:yaml.org,2002:int"),
            long => new TagName("tag:yaml.org,2002:int"),
            System.Numerics.BigInteger => new TagName("tag:yaml.org,2002:int"),
            float => new TagName("tag:yaml.org,2002:float"),
            double => new TagName("tag:yaml.org,2002:float"),
            decimal => new TagName("tag:yaml.org,2002:float"),
            bool => new TagName("tag:yaml.org,2002:bool"),
            string => new TagName("tag:yaml.org,2002:str"),
            DateTime => new TagName("tag:yaml.org,2002:timestamp"),
            _ => TagName.Empty
        };
    }

    #endregion

    #region Helper Methods

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

    #endregion
}
