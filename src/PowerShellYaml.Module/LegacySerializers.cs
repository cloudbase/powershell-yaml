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

#nullable disable

namespace PowerShellYaml.Module;

using System;
using System.IO;
using System.Numerics;
using System.Text.RegularExpressions;
using System.Collections;
using System.Management.Automation;
using System.Collections.Generic;
using YamlDotNet.Core;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.EventEmitters;
using YamlDotNet.Core.Events;
using YamlDotNet.Serialization.NamingConventions;
using YamlDotNet.Serialization.ObjectGraphVisitors;
using YamlDotNet.Serialization.ObjectGraphTraversalStrategies;
using YamlDotNet.Serialization.ObjectFactories;
using YamlDotNet.RepresentationModel;


/// <summary>
/// Shared depth tracker for type converters
/// Thread-static to ensure thread safety
/// </summary>
internal static class SharedDepthTracker {
    [ThreadStatic]
    private static int currentDepth;

    public static int CurrentDepth => currentDepth;

    public static void Increment() => currentDepth++;
    public static void Decrement() => currentDepth--;
}

internal static class PSObjectHelper {
    /// <summary>
    /// Unwraps a PSObject to its BaseObject if the BaseObject is not a PSCustomObject.
    /// </summary>
    /// <param name="obj">The object to potentially unwrap</param>
    /// <param name="unwrappedType">The type of the unwrapped object</param>
    /// <returns>The unwrapped object if it was a PSObject wrapping a non-PSCustomObject, otherwise the original object</returns>
    public static object UnwrapIfNeeded(object obj, out Type unwrappedType) {
        if (obj is PSObject psObj && psObj.BaseObject != null) {
            var baseType = psObj.BaseObject.GetType();
            if (baseType != typeof(System.Management.Automation.PSCustomObject)) {
                unwrappedType = baseType;
                return psObj.BaseObject;
            }
        }
        unwrappedType = obj?.GetType();
        return obj;
    }
}

public class BigIntegerTypeConverter : IYamlTypeConverter {
    public bool Accepts(Type type) {
        return typeof(BigInteger).IsAssignableFrom(type);
    }

    public object ReadYaml(IParser parser, Type type, ObjectDeserializer rootDeserializer) {
        var value = parser.Consume<Scalar>().Value;
        var bigNr = BigInteger.Parse(value);
        return bigNr;
    }

    public void WriteYaml(IEmitter emitter, object value, Type type, ObjectSerializer serializer) {
        var bigNr = (BigInteger)value;
        emitter.Emit(new Scalar(AnchorName.Empty, TagName.Empty, bigNr.ToString(), ScalarStyle.Plain, true, false));
    }
}

public class IDictionaryTypeConverter :  IYamlTypeConverter {

    private bool omitNullValues;
    private bool useFlowStyle;
    private readonly int maxDepth;

    public IDictionaryTypeConverter(bool omitNullValues = false, bool useFlowStyle = false, int maxDepth = 100) {
        this.omitNullValues = omitNullValues;
        this.useFlowStyle = useFlowStyle;
        this.maxDepth = maxDepth;
    }

    public bool Accepts(Type type) {
        return typeof(IDictionary).IsAssignableFrom(type);
    }

    public object ReadYaml(IParser parser, Type type, ObjectDeserializer rootDeserializer) {
        var deserializedObject = rootDeserializer(typeof(IDictionary<string, object>)) as IDictionary;
        return deserializedObject;
    }

    public void WriteYaml(IEmitter emitter, object value, Type type, ObjectSerializer serializer) {
        var hObj = (IDictionary)value;
        var mappingStyle = this.useFlowStyle ? MappingStyle.Flow : MappingStyle.Block;

        SharedDepthTracker.Increment();
        try {
            // Check if we've exceeded the depth limit
            if (SharedDepthTracker.CurrentDepth > maxDepth) {
                // Emit empty object as we're too deep
                emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, MappingStyle.Flow));
                emitter.Emit(new MappingEnd());
                return;
            }

            emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, mappingStyle));

            foreach (DictionaryEntry entry in hObj) {
                if(entry.Value == null) {
                    if (this.omitNullValues) {
                        continue;
                    }
                    serializer(entry.Key, entry.Key.GetType());
                    emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
                    continue;
                }

                serializer(entry.Key, entry.Key.GetType());

                var unwrapped = PSObjectHelper.UnwrapIfNeeded(entry.Value, out var unwrappedType);
                serializer(unwrapped, unwrappedType);
            }
        } finally {
            SharedDepthTracker.Decrement();
        }

        emitter.Emit(new MappingEnd());
    }
}

public class PSObjectTypeConverter : IYamlTypeConverter {

    private readonly bool omitNullValues;
    private readonly bool useFlowStyle;
    private readonly int maxDepth;

    public PSObjectTypeConverter(bool omitNullValues = false, bool useFlowStyle = false, int maxDepth = 100) {
        this.omitNullValues = omitNullValues;
        this.useFlowStyle = useFlowStyle;
        this.maxDepth = maxDepth;
    }

    public bool Accepts(Type type) {
        return typeof(PSObject).IsAssignableFrom(type);
    }

    public object ReadYaml(IParser parser, Type type, ObjectDeserializer rootDeserializer)
    {
        // We don't really need to do any custom deserialization.
        var deserializedObject = rootDeserializer(typeof(IDictionary<string, object>)) as IDictionary;
        return deserializedObject;
    }

    public void WriteYaml(IEmitter emitter, object value, Type type, ObjectSerializer serializer) {
        var psObj = (PSObject)value;
        if (psObj.BaseObject != null &&
            !typeof(IDictionary).IsAssignableFrom(psObj.BaseObject.GetType()) &&
            !typeof(PSCustomObject).IsAssignableFrom(psObj.BaseObject.GetType())) {
            serializer(psObj.BaseObject, psObj.BaseObject.GetType());
            return;
        }
        var mappingStyle = this.useFlowStyle ? MappingStyle.Flow : MappingStyle.Block;

        SharedDepthTracker.Increment();
        try {
            // Check if we've exceeded the depth limit
            if (SharedDepthTracker.CurrentDepth > maxDepth) {
                // Emit empty object as we're too deep
                emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, MappingStyle.Flow));
                emitter.Emit(new MappingEnd());
                return;
            }

            emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, mappingStyle));

            foreach (var prop in psObj.Properties) {
                if (prop.Value == null) {
                    if (this.omitNullValues) {
                        continue;
                    }
                    serializer(prop.Name, prop.Name.GetType());
                    emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
                } else {
                    serializer(prop.Name, prop.Name.GetType());

                    var unwrapped = PSObjectHelper.UnwrapIfNeeded(prop.Value, out var unwrappedType);
                    serializer(unwrapped, unwrappedType);
                }
            }

            emitter.Emit(new MappingEnd());
        } finally {
            SharedDepthTracker.Decrement();
        }
    }
}

public class StringQuotingEmitter: ChainedEventEmitter {
    // Patterns from https://yaml.org/spec/1.2/spec.html#id2804356
    private static Regex quotedRegex = new Regex(@"^(\~|null|true|false|on|off|yes|no|y|n|[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?|[-+]?(\.inf))?$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    public StringQuotingEmitter(IEventEmitter next): base(next) {}

    public override void Emit(ScalarEventInfo eventInfo, IEmitter emitter) {
        var typeCode = eventInfo.Source.Value != null
        ? Type.GetTypeCode(eventInfo.Source.Type)
        : TypeCode.Empty;

        switch (typeCode) {
            case TypeCode.Char:
                if (Char.IsDigit((char)eventInfo.Source.Value)) {
                    eventInfo.Style = ScalarStyle.DoubleQuoted;
                }
                break;
            case TypeCode.String:
                var val = eventInfo.Source.Value.ToString();
                if (quotedRegex.IsMatch(val))
                {
                    eventInfo.Style = ScalarStyle.DoubleQuoted;
                } else if (val.IndexOf('\n') > -1) {
                    eventInfo.Style = ScalarStyle.Literal;
        }
                break;
        }

        base.Emit(eventInfo, emitter);
    }
}

public class FlowStyleAllEmitter(IEventEmitter next) : ChainedEventEmitter(next) {
    public override void Emit(MappingStartEventInfo eventInfo, IEmitter emitter) {
        eventInfo.Style = MappingStyle.Flow;
        base.Emit(eventInfo, emitter);
    }

    public override void Emit(SequenceStartEventInfo eventInfo, IEmitter emitter){
        eventInfo.Style = SequenceStyle.Flow;
        base.Emit(eventInfo, emitter);
    }
}

public class FlowStyleSequenceEmitter(IEventEmitter next) : ChainedEventEmitter(next) {
    public override void Emit(SequenceStartEventInfo eventInfo, IEmitter emitter){
        eventInfo.Style = SequenceStyle.Flow;
        base.Emit(eventInfo, emitter);
    }
}

/// <summary>
/// Custom traversal strategy that limits recursion depth
/// Note: This only affects objects that don't have custom type converters.
/// Hashtables and PSCustomObjects use type converters that bypass this strategy.
/// </summary>
public class DepthLimitingTraversalStrategy(
    ITypeInspector typeInspector,
    ITypeResolver typeResolver,
    int maxRecursion,
    INamingConvention namingConvention,
    IObjectFactory objectFactory) : FullObjectGraphTraversalStrategy(typeInspector, typeResolver, 1000, namingConvention, objectFactory)
{
    private readonly int _maxDepth = maxRecursion;

    protected override void Traverse<TContext>(
        IPropertyDescriptor propertyDescriptor,
        object value,
        IObjectDescriptor valueDescriptor,
        IObjectGraphVisitor<TContext> visitor,
        TContext context,
        Stack<ObjectPathSegment> path,
        ObjectSerializer serializer)
    {
        int maxDepth = _maxDepth;
        if (maxDepth == 0)
        {
            maxDepth = 1;
        }

        // Check if we should skip this property due to depth limit
        // Use path.Count as fallback for .NET objects that don't go through type converters
        // path.Count starts at 1 for root properties, so subtract 1 to get 0-based depth
        int effectiveDepth = Math.Max(SharedDepthTracker.CurrentDepth, path.Count - 1);

        // Skip if we're beyond the depth limit
        // Note: depth 0 = root object properties, depth 1 = nested properties, etc.
        if(effectiveDepth > maxDepth)
        {
            // Return here and do not traverse. Max depth reached.
            return;
        }

        // Call base implementation to do the actual traversal
        base.Traverse(propertyDescriptor, value, valueDescriptor, visitor, context, path, serializer);
    }
}

public class BuilderUtils {
    public static SerializerBuilder BuildSerializer(
        SerializerBuilder builder,
        bool omitNullValues = false,
        bool useFlowStyle = false,
        bool useSequenceFlowStyle = false,
        bool useBlockStyle = false,
        bool useSequenceBlockStyle = false,
        bool jsonCompatible = false,
        int maxDepth = 100) {

        if (jsonCompatible) {
            useFlowStyle = true;
            useSequenceFlowStyle = true;
        }

        // Block style takes precedence over flow style if both are set
        if (useBlockStyle) {
            useFlowStyle = false;
        }
        if (useSequenceBlockStyle) {
            useSequenceFlowStyle = false;
        }

        // Use custom traversal strategy for depth limiting
        // Note: This only affects objects without custom type converters
        builder = builder.WithObjectGraphTraversalStrategyFactory((typeInspector, typeResolver, typeConverters, maximumRecursion) =>
            new DepthLimitingTraversalStrategy(
                typeInspector,
                typeResolver,
                maxDepth,
                NullNamingConvention.Instance,
                new DefaultObjectFactory()
            )
        );

        builder = builder
            .WithEventEmitter(next => new StringQuotingEmitter(next))
            .WithTypeConverter(new BigIntegerTypeConverter())
            .WithTypeConverter(new IDictionaryTypeConverter(omitNullValues, useFlowStyle, maxDepth))
            .WithTypeConverter(new PSObjectTypeConverter(omitNullValues, useFlowStyle, maxDepth));

        if (useFlowStyle) {
            builder = builder.WithEventEmitter(next => new FlowStyleAllEmitter(next));
        }
        if (useSequenceFlowStyle) {
            builder = builder.WithEventEmitter(next => new FlowStyleSequenceEmitter(next));
        }

        return builder;
    }
}

/// <summary>
/// Metadata storage for individual YAML properties
/// </summary>
public class YamlPropertyMetadata {
    public string Comment { get; set; }
    public string Tag { get; set; }
    public string Anchor { get; set; }
    public string Alias { get; set; }
    public ScalarStyle? ScalarStyle { get; set; }
    public MappingStyle? MappingStyle { get; set; }
    public SequenceStyle? SequenceStyle { get; set; }
}

/// <summary>
/// Metadata store for an object/document
/// </summary>
public class YamlMetadataStore {
    private readonly Dictionary<string, YamlPropertyMetadata> _propertyMetadata = new Dictionary<string, YamlPropertyMetadata>();
    private readonly Dictionary<string, YamlMetadataStore> _nestedObjectMetadata = new Dictionary<string, YamlMetadataStore>();

    public string DocumentComment { get; set; }
    public MappingStyle? DocumentMappingStyle { get; set; }

    public void SetPropertyComment(string propertyName, string comment) {
        GetOrCreatePropertyMetadata(propertyName).Comment = comment;
    }

    public string GetPropertyComment(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.Comment
            : null;
    }

    public void SetPropertyStyle(string propertyName, MappingStyle style) {
        GetOrCreatePropertyMetadata(propertyName).MappingStyle = style;
    }

    public MappingStyle? GetPropertyStyle(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.MappingStyle
            : null;
    }

    public void SetPropertyScalarStyle(string propertyName, ScalarStyle style) {
        GetOrCreatePropertyMetadata(propertyName).ScalarStyle = style;
    }

    public ScalarStyle? GetPropertyScalarStyle(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.ScalarStyle
            : null;
    }

    public void SetPropertyMappingStyle(string propertyName, MappingStyle style) {
        GetOrCreatePropertyMetadata(propertyName).MappingStyle = style;
    }

    public MappingStyle? GetPropertyMappingStyle(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.MappingStyle
            : null;
    }

    public void SetPropertySequenceStyle(string propertyName, SequenceStyle style) {
        GetOrCreatePropertyMetadata(propertyName).SequenceStyle = style;
    }

    public SequenceStyle? GetPropertySequenceStyle(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.SequenceStyle
            : null;
    }

    public void SetPropertyTag(string propertyName, string tag) {
        GetOrCreatePropertyMetadata(propertyName).Tag = tag;
    }

    public string GetPropertyTag(string propertyName) {
        return _propertyMetadata.TryGetValue(propertyName, out var metadata)
            ? metadata.Tag
            : null;
    }

    public YamlMetadataStore GetNestedMetadata(string propertyName) {
        if (!_nestedObjectMetadata.TryGetValue(propertyName, out var metadata)) {
            metadata = new YamlMetadataStore();
            _nestedObjectMetadata[propertyName] = metadata;
        }
        return metadata;
    }

    private YamlPropertyMetadata GetOrCreatePropertyMetadata(string propertyName) {
        if (!_propertyMetadata.TryGetValue(propertyName, out var metadata)) {
            metadata = new YamlPropertyMetadata();
            _propertyMetadata[propertyName] = metadata;
        }
        return metadata;
    }
}

/// <summary>
/// Parser that preserves YAML metadata (comments, tags, styles) while parsing
/// Uses low-level Parser API with Scanner(skipComments: false) to capture comment tokens
/// </summary>
public static class YamlDocumentParser {
    public static (object data, YamlMetadataStore metadata) ParseWithMetadata(string yaml, bool allowDuplicateKeys = false) {
        if (string.IsNullOrEmpty(yaml)) {
            return (null, null);
        }

        var stringReader = new StringReader(yaml);
        // Use Scanner with skipComments=false to enable comment parsing
        var scanner = new Scanner(stringReader, skipComments: false);
        var parser = new Parser(scanner);
        var metadata = new YamlMetadataStore();

        // Consume stream start
        parser.Consume<StreamStart>();

        // Check for document start
        if (!parser.Accept<DocumentStart>(out var _)) {
            return (null, null);
        }

        parser.Consume<DocumentStart>();

        // Check if document has content
        if (parser.Accept<DocumentEnd>(out var _)) {
            parser.Consume<DocumentEnd>();
            parser.Consume<StreamEnd>();
            return (null, null);
        }

        // Parse the root value
        string pendingComment = null;

        // Capture the root document mapping style if it's a mapping
        if (parser.Accept<MappingStart>(out var rootMapping)) {
            metadata.DocumentMappingStyle = rootMapping.Style;
        }

        var data = ParseValue(parser, metadata, "", ref pendingComment, allowDuplicateKeys);

        // Consume document end and stream end
        parser.Consume<DocumentEnd>();
        parser.Consume<StreamEnd>();

        return (data, metadata);
    }

    private static object ParseValue(IParser parser, YamlMetadataStore metadata, string path, ref string pendingComment, bool allowDuplicateKeys) {
        // Capture any comments before the value
        while (parser.Accept<Comment>(out var commentEvent)) {
            parser.Consume<Comment>();
            // Store the comment - it will be associated with the next key/value
            pendingComment = commentEvent.Value;
        }

        if (parser.Accept<Scalar>(out var _)) {
            return ParseScalar(parser.Consume<Scalar>());
        }
        else if (parser.Accept<MappingStart>(out var _)) {
            return ParseMapping(parser, metadata, path, ref pendingComment, allowDuplicateKeys);
        }
        else if (parser.Accept<SequenceStart>(out var _)) {
            return ParseSequence(parser, metadata, path, ref pendingComment, allowDuplicateKeys);
        }
        else if (parser.Accept<AnchorAlias>(out var _)) {
            // Handle alias - for now just consume it
            // TODO: Implement anchor/alias preservation in a future version
            parser.Consume<AnchorAlias>();
            return null;
        }

        return null;
    }

    private static object ParseMapping(IParser parser, YamlMetadataStore metadata, string path, ref string pendingComment, bool allowDuplicateKeys) {
        parser.Consume<MappingStart>();
        var dict = new Dictionary<object, object>();
        // Track keys case-insensitively to detect duplicates
        var seenKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        // Use any pending comment from before MappingStart
        string pendingBlockComment = pendingComment;
        pendingComment = null;

        while (!parser.Accept<MappingEnd>(out var _)) {
            // Use pending block comment from previous iteration if available
            string blockComment = pendingBlockComment;
            pendingBlockComment = null;

            // Capture any additional block comments before this key
            while (parser.Accept<Comment>(out var _)) {
                var commentEvent = parser.Consume<Comment>();
                if (!commentEvent.IsInline && blockComment == null) {
                    blockComment = commentEvent.Value;
                }
            }

            // Parse key
            if (!parser.Accept<Scalar>(out var _)) {
                // No more keys, break
                break;
            }

            var keyScalar = parser.Consume<Scalar>();
            var key = keyScalar.Value;

            // Check for duplicate keys (case-insensitive)
            bool isDuplicate = !seenKeys.Add(key);
            if (isDuplicate && !allowDuplicateKeys) {
                throw new InvalidOperationException(
                    $"Duplicate key '{key}' found in YAML mapping at path '{path}'. " +
                    "YAML keys are case-insensitive and duplicates are not allowed to prevent data loss. " +
                    "For typed objects, use [YamlKey] attribute to map different case variations to separate properties.");
            }

            // Peek at the value to get tag and style before consuming
            string valueTag = null;
            ScalarStyle? scalarStyle = null;
            MappingStyle? mappingStyle = null;
            SequenceStyle? sequenceStyle = null;

            if (parser.Accept<Scalar>(out var scalarPeek)) {
                if (!scalarPeek.Tag.IsEmpty) {
                    valueTag = scalarPeek.Tag.Value;
                }
                scalarStyle = scalarPeek.Style;
            }
            else if (parser.Accept<MappingStart>(out var mappingPeek)) {
                mappingStyle = mappingPeek.Style;
                if (!mappingPeek.Tag.IsEmpty) {
                    valueTag = mappingPeek.Tag.Value;
                }
            }
            else if (parser.Accept<SequenceStart>(out var sequencePeek)) {
                sequenceStyle = sequencePeek.Style;
                if (!sequencePeek.Tag.IsEmpty) {
                    valueTag = sequencePeek.Tag.Value;
                }
            }

            // Parse value recursively
            var childPath = string.IsNullOrEmpty(path) ? key : $"{path}.{key}";
            var childMetadata = metadata.GetNestedMetadata(key);
            string childComment = null;
            var value = ParseValue(parser, childMetadata, childPath, ref childComment, allowDuplicateKeys);

            // If child returned a pending comment and we don't have one yet, use it for next sibling
            if (!string.IsNullOrEmpty(childComment) && string.IsNullOrEmpty(pendingBlockComment)) {
                pendingBlockComment = childComment;
            }

            // Store tag if present
            if (!string.IsNullOrEmpty(valueTag)) {
                metadata.SetPropertyTag(key, valueTag);
            }

            // Store styles if present
            if (scalarStyle.HasValue) {
                metadata.SetPropertyScalarStyle(key, scalarStyle.Value);
            }
            if (mappingStyle.HasValue) {
                metadata.SetPropertyMappingStyle(key, mappingStyle.Value);
            }
            if (sequenceStyle.HasValue) {
                metadata.SetPropertySequenceStyle(key, sequenceStyle.Value);
            }

            // Capture comments after value
            // Inline comments (IsInline=true) belong to current key
            // Block comments (IsInline=false) belong to next key
            string inlineComment = null;
            while (parser.Accept<Comment>(out var _)) {
                var commentEvent = parser.Consume<Comment>();
                if (commentEvent.IsInline) {
                    inlineComment = commentEvent.Value;
                } else {
                    // This block comment belongs to the next key
                    pendingBlockComment = commentEvent.Value;
                }
            }

            // Store comment - prefer inline comment over block comment
            if (!string.IsNullOrEmpty(inlineComment)) {
                metadata.SetPropertyComment(key, inlineComment.Trim());
            } else if (!string.IsNullOrEmpty(blockComment)) {
                metadata.SetPropertyComment(key, blockComment.Trim());
            }

            dict[key] = value;
        }

        parser.Consume<MappingEnd>();

        // Pass any pending block comment up to parent level
        pendingComment = pendingBlockComment;

        return dict;
    }

    private static object ParseSequence(IParser parser, YamlMetadataStore metadata, string path, ref string pendingComment, bool allowDuplicateKeys) {
        parser.Consume<SequenceStart>();
        var list = new List<object>();
        int index = 0;

        while (!parser.Accept<SequenceEnd>(out var _)) {
            // Capture comment before sequence item
            string itemComment = null;
            while (parser.Accept<Comment>(out var commentEvent)) {
                parser.Consume<Comment>();
                itemComment = commentEvent.Value;
            }

            var childPath = $"{path}[{index}]";
            var childMetadata = metadata.GetNestedMetadata($"[{index}]");
            var value = ParseValue(parser, childMetadata, childPath, ref itemComment, allowDuplicateKeys);

            list.Add(value);
            index++;
        }

        parser.Consume<SequenceEnd>();

        // Note: sequences don't have pending comments to pass up
        // (comments are associated with items, not with the sequence itself)

        return list;
    }

    private static object ParseScalar(Scalar scalar) {
        // Use existing type conversion logic
        var value = scalar.Value;
        var tag = scalar.Tag;
        var style = scalar.Style;

        // Check for null values first (only for plain style)
        if (style == ScalarStyle.Plain && (value == "" || value == "~" || value == "null" || value == "Null" || value == "NULL")) {
            return null;
        }

        // Handle YAML tags for explicit type conversion (tags override everything)
        if (!tag.IsEmpty) {
            var tagValue = tag.Value;

            switch (tagValue) {
                case "tag:yaml.org,2002:int":
                    // Parse as BigInteger first (handles all integer sizes)
                    // Use Float | Integer NumberStyles to match legacy behavior
                    if (System.Numerics.BigInteger.TryParse(value, System.Globalization.NumberStyles.Float | System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var bigIntValue)) {
                        // Try to fit into smaller int types
                        if (bigIntValue >= int.MinValue && bigIntValue <= int.MaxValue) {
                            return (int)bigIntValue;
                        }
                        if (bigIntValue >= long.MinValue && bigIntValue <= long.MaxValue) {
                            return (long)bigIntValue;
                        }
                        return bigIntValue;
                    } else {
                        throw new FormatException($"Value '{value}' cannot be parsed as an integer (tag: {tagValue})");
                    }
                case "tag:yaml.org,2002:float":
                    // Parse as decimal (preferred over double for precision)
                    if (decimal.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var decimalValue)) {
                        return decimalValue;
                    } else {
                        throw new FormatException($"Value '{value}' cannot be parsed as a float (tag: {tagValue})");
                    }
                case "tag:yaml.org,2002:timestamp":
                    // Parse as DateTime
                    if (DateTime.TryParse(value, null, System.Globalization.DateTimeStyles.RoundtripKind, out var dateTimeValue)) {
                        return dateTimeValue;
                    } else {
                        throw new FormatException($"Value '{value}' cannot be parsed as a timestamp (tag: {tagValue})");
                    }
                case "tag:yaml.org,2002:bool":
                    if (bool.TryParse(value, out var boolValue)) {
                        return boolValue;
                    } else {
                        throw new FormatException($"Value '{value}' cannot be parsed as a boolean (tag: {tagValue})");
                    }
                case "tag:yaml.org,2002:str":
                    return value;
                case "tag:yaml.org,2002:null":
                    return null;
                case "!":
                    return value;
            }
        }

        // No tag - check if quoted (quoted scalars are always strings)
        if (style == ScalarStyle.SingleQuoted || style == ScalarStyle.DoubleQuoted ||
            style == ScalarStyle.Literal || style == ScalarStyle.Folded) {
            return value;
        }

        // Try to parse as boolean
        if (bool.TryParse(value, out var inferredBool)) {
            return inferredBool;
        }

        // Try to parse as integer (check for very large numbers)
        // Use Float | Integer NumberStyles to match legacy behavior
        if (System.Numerics.BigInteger.TryParse(value, System.Globalization.NumberStyles.Float | System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var inferredBigInt)) {
            // Try to fit into smaller int types
            if (inferredBigInt >= int.MinValue && inferredBigInt <= int.MaxValue) {
                return (int)inferredBigInt;
            }
            if (inferredBigInt >= long.MinValue && inferredBigInt <= long.MaxValue) {
                return (long)inferredBigInt;
            }
            return inferredBigInt;
        }

        // Try to parse as decimal
        if (decimal.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var inferredDecimal)) {
            return inferredDecimal;
        }

        // Try to parse as DateTime (ISO8601 formats)
        if (DateTime.TryParse(value, null, System.Globalization.DateTimeStyles.RoundtripKind, out var inferredDateTime)) {
            // Only treat as DateTime if it looks like ISO8601
            if (value.Contains("T") || value.Contains("-")) {
                return inferredDateTime;
            }
        }

        // Return as string
        return value;
    }
}

/// <summary>
/// Extension methods for creating and managing PSCustomObjects with YAML metadata
/// </summary>
public static class PSObjectMetadataExtensions {
    private const string MetadataPropertyName = "__psyaml_metadata";
    private const string TypeMarker = "PSYaml.EnhancedPSCustomObject";

    /// <summary>
    /// Creates an enhanced PSCustomObject from dictionary data and metadata
    /// </summary>
    public static PSObject CreateEnhancedPSCustomObject(IDictionary data, YamlMetadataStore metadata) {
        var pso = new PSObject();

        // Add all properties from dictionary
        foreach (DictionaryEntry entry in data) {
            var value = entry.Value;
            var key = entry.Key.ToString();

            // Recursively enhance nested objects
            if (value is IDictionary nestedDict) {
                var nestedMetadata = metadata.GetNestedMetadata(key);
                value = CreateEnhancedPSCustomObject(nestedDict, nestedMetadata);
            }
            else if (value is IList nestedList) {
                // Enhance array elements if needed
                value = EnhanceList(nestedList, metadata.GetNestedMetadata(key));
            }

            pso.Properties.Add(new PSNoteProperty(key, value));
        }

        // Attach metadata store as hidden property
        var metaProp = new PSNoteProperty(MetadataPropertyName, metadata);
        pso.Properties.Add(metaProp);

        // Add type marker for identification
        pso.TypeNames.Insert(0, TypeMarker);

        return pso;
    }

    /// <summary>
    /// Enhances list items by recursively converting dictionaries to enhanced PSCustomObjects
    /// </summary>
    private static IList EnhanceList(IList list, YamlMetadataStore metadata) {
        var enhanced = new List<object>();
        for (int i = 0; i < list.Count; i++) {
            var item = list[i];
            if (item is IDictionary dict) {
                enhanced.Add(CreateEnhancedPSCustomObject(dict, metadata.GetNestedMetadata($"[{i}]")));
            } else {
                enhanced.Add(item);
            }
        }
        return enhanced;
    }

    /// <summary>
    /// Checks if a PSObject is an enhanced PSCustomObject with YAML metadata
    /// </summary>
    public static bool IsEnhancedPSCustomObject(PSObject obj) {
        return obj != null && obj.TypeNames.Contains(TypeMarker);
    }

    /// <summary>
    /// Retrieves the YAML metadata from an enhanced PSCustomObject
    /// </summary>
    public static YamlMetadataStore GetMetadata(PSObject obj) {
        if (obj == null) {
            return null;
        }
        var metaProp = obj.Properties[MetadataPropertyName];
        return metaProp?.Value as YamlMetadataStore;
    }
}

/// <summary>
/// Serializes enhanced PSCustomObjects with metadata (comments, styles) to YAML
/// </summary>
public static class MetadataAwareSerializer {
    /// <summary>
    /// Checks if a YAML tag should be emitted for the current value
    /// </summary>
    private static bool ShouldEmitTag(string tag, Type type) {
        if (string.IsNullOrEmpty(tag)) {
            return false;
        }

        // The non-specific tag "!" should always be emitted to prevent type inference
        if (tag == "!") {
            return true;
        }

        // Custom tags (starting with "!") should always be emitted for round-trip preservation
        if (tag.StartsWith("!") && tag.Length > 1) {
            return true;
        }

        if (type == null) {
            return false;
        }

        // Map standard YAML tags to .NET types - only emit if they match
        return tag switch
        {
            "tag:yaml.org,2002:str" => type == typeof(string),
            "tag:yaml.org,2002:int" => type == typeof(int) || type == typeof(long) || type == typeof(BigInteger),
            "tag:yaml.org,2002:float" => type == typeof(float) || type == typeof(double) || type == typeof(decimal),
            "tag:yaml.org,2002:bool" => type == typeof(bool),
            "tag:yaml.org,2002:null" => type == null,
            "tag:yaml.org,2002:timestamp" => type == typeof(DateTime),
            _ => false,// Unknown standard tag - don't emit
        };
    }

    private static string GetTagFromType(object value) {
        return value switch
        {
            int => "tag:yaml.org,2002:int",
            long => "tag:yaml.org,2002:int",
            System.Numerics.BigInteger => "tag:yaml.org,2002:int",
            float => "tag:yaml.org,2002:float",
            double => "tag:yaml.org,2002:float",
            decimal => "tag:yaml.org,2002:float",
            bool => "tag:yaml.org,2002:bool",
            string => "tag:yaml.org,2002:str",
            DateTime => "tag:yaml.org,2002:timestamp",
            _ => string.Empty
        };
    }

    public static string Serialize(PSObject obj, bool indentedSequences = false, bool emitTags = false, int maxDepth = 100) {
        var metadata = PSObjectMetadataExtensions.GetMetadata(obj);
        if (metadata == null) {
            throw new InvalidOperationException("Object does not have YAML metadata");
        }

        var stringWriter = new StringWriter();

        // Create emitter with or without indented sequences
        IEmitter emitter;
        if (indentedSequences) {
            // Use EmitterSettings to enable indented sequences
            var emitterSettings = new EmitterSettings(
                bestIndent: 2,
                bestWidth: int.MaxValue,
                isCanonical: false,
                maxSimpleKeyLength: 1024,
                skipAnchorName: false,
                indentSequences: true
            );
            emitter = new Emitter(stringWriter, emitterSettings);
        } else {
            emitter = new Emitter(stringWriter);
        }

        emitter.Emit(new StreamStart());
        emitter.Emit(new DocumentStart());

        SerializePSObject(obj, metadata, emitter, MappingStyle.Block, emitTags, 0, maxDepth);

        emitter.Emit(new DocumentEnd(true));
        emitter.Emit(new StreamEnd());

        return stringWriter.ToString();
    }

    private static void SerializePSObject(PSObject obj, YamlMetadataStore metadata, IEmitter emitter, MappingStyle style = MappingStyle.Block, bool emitTags = false, int currentDepth = 0, int maxDepth = 100) {
        if (currentDepth >= maxDepth) {
            // Emit empty object as default value for the truncated type
            emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, MappingStyle.Flow));
            emitter.Emit(new MappingEnd());
            return;
        }
        emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, style));

        foreach (var prop in obj.Properties) {
            // Skip internal metadata property
            if (prop.Name == "__psyaml_metadata") continue;

            // Emit comment if present
            var comment = metadata.GetPropertyComment(prop.Name);
            if (!string.IsNullOrEmpty(comment)) {
                emitter.Emit(new Comment(comment, false));
            }

            // Emit key
            emitter.Emit(new Scalar(prop.Name));

            // Get stored tag and scalar style for this property
            var storedTag = metadata.GetPropertyTag(prop.Name);
            var scalarStyle = metadata.GetPropertyScalarStyle(prop.Name) ?? ScalarStyle.Any;

            // Emit value
            if (prop.Value == null) {
                emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
            }
            else if (prop.Value is PSObject nestedPSObj && PSObjectMetadataExtensions.IsEnhancedPSCustomObject(nestedPSObj)) {
                // Recursively serialize nested enhanced objects
                var nestedMetadata = metadata.GetNestedMetadata(prop.Name);
                var nestedMappingStyle = metadata.GetPropertyMappingStyle(prop.Name) ?? MappingStyle.Block;
                SerializePSObject(nestedPSObj, nestedMetadata, emitter, nestedMappingStyle, emitTags, currentDepth + 1, maxDepth);
            }
            else if (prop.Value is IList list) {
                var sequenceStyle = metadata.GetPropertySequenceStyle(prop.Name) ?? SequenceStyle.Block;
                SerializeList(list, metadata.GetNestedMetadata(prop.Name), emitter, sequenceStyle, emitTags, currentDepth + 1, maxDepth);
            }
            else if (prop.Value is bool boolValue) {
                // If emitTags is enabled and no stored tag, infer tag from type
                var tagToUse = storedTag;
                if (emitTags && string.IsNullOrEmpty(storedTag)) {
                    tagToUse = GetTagFromType(prop.Value);
                }
                var shouldEmitTag = !string.IsNullOrEmpty(tagToUse) && (emitTags || ShouldEmitTag(tagToUse, typeof(bool)));
                var tag = shouldEmitTag ? tagToUse : TagName.Empty;
                var isImplicit = !shouldEmitTag;  // Implicit if no tag is being emitted
                emitter.Emit(new Scalar(AnchorName.Empty, tag, boolValue ? "true" : "false", scalarStyle, isImplicit, false));
            }
            else if (prop.Value is System.Numerics.BigInteger bigInt) {
                // If emitTags is enabled and no stored tag, infer tag from type
                var tagToUse = storedTag;
                if (emitTags && string.IsNullOrEmpty(storedTag)) {
                    tagToUse = GetTagFromType(prop.Value);
                }
                var shouldEmitTag = !string.IsNullOrEmpty(tagToUse) && (emitTags || ShouldEmitTag(tagToUse, typeof(BigInteger)));
                var tag = shouldEmitTag ? tagToUse : TagName.Empty;
                var isImplicit = !shouldEmitTag;
                emitter.Emit(new Scalar(AnchorName.Empty, tag, bigInt.ToString(), scalarStyle, isImplicit, false));
            }
            else if (prop.Value is DateTime dateTime) {
                // If emitTags is enabled and no stored tag, infer tag from type
                var tagToUse = storedTag;
                if (emitTags && string.IsNullOrEmpty(storedTag)) {
                    tagToUse = GetTagFromType(prop.Value);
                }
                var shouldEmitTag = !string.IsNullOrEmpty(tagToUse) && (emitTags || ShouldEmitTag(tagToUse, typeof(DateTime)));
                var tag = shouldEmitTag ? tagToUse : TagName.Empty;
                var isImplicit = !shouldEmitTag;
                emitter.Emit(new Scalar(AnchorName.Empty, tag, dateTime.ToString("o"), scalarStyle, isImplicit, false));
            }
            else {
                // If emitTags is enabled and no stored tag, infer tag from type
                var tagToUse = storedTag;
                if (emitTags && string.IsNullOrEmpty(storedTag)) {
                    tagToUse = GetTagFromType(prop.Value);
                }
                var valueType = prop.Value.GetType();
                var shouldEmitTag = !string.IsNullOrEmpty(tagToUse) && (emitTags || ShouldEmitTag(tagToUse, valueType));
                var tag = shouldEmitTag ? tagToUse : TagName.Empty;
                var isImplicit = !shouldEmitTag;  // Implicit if no tag is being emitted
                emitter.Emit(new Scalar(AnchorName.Empty, tag, prop.Value.ToString(), scalarStyle, isImplicit, false));
            }
        }

        emitter.Emit(new MappingEnd());
    }

    private static void SerializeList(IList list, YamlMetadataStore metadata, IEmitter emitter, SequenceStyle style = SequenceStyle.Block, bool emitTags = false, int currentDepth = 0, int maxDepth = 100) {
        if (currentDepth >= maxDepth) {
            // Emit empty array as default value for the truncated type
            emitter.Emit(new SequenceStart(AnchorName.Empty, TagName.Empty, true, SequenceStyle.Flow));
            emitter.Emit(new SequenceEnd());
            return;
        }
        emitter.Emit(new SequenceStart(AnchorName.Empty, TagName.Empty, true, style));

        for (int i = 0; i < list.Count; i++) {
            var item = list[i];

            if (item == null) {
                emitter.Emit(new Scalar("null"));
            }
            else if (item is PSObject nestedPSObj && PSObjectMetadataExtensions.IsEnhancedPSCustomObject(nestedPSObj)) {
                var itemMetadata = metadata.GetNestedMetadata($"[{i}]");
                SerializePSObject(nestedPSObj, itemMetadata, emitter, MappingStyle.Block, emitTags, currentDepth + 1, maxDepth);
            }
            else if (item is bool boolValue) {
                // If emitTags is enabled, infer tag from type
                if (emitTags) {
                    var tag = GetTagFromType(item);
                    emitter.Emit(new Scalar(AnchorName.Empty, tag, boolValue ? "true" : "false", ScalarStyle.Any, false, false));
                } else {
                    emitter.Emit(new Scalar(boolValue ? "true" : "false"));
                }
            }
            else if (item is System.Numerics.BigInteger bigInt) {
                // If emitTags is enabled, infer tag from type
                if (emitTags) {
                    var tag = GetTagFromType(item);
                    emitter.Emit(new Scalar(AnchorName.Empty, tag, bigInt.ToString(), ScalarStyle.Plain, false, false));
                } else {
                    emitter.Emit(new Scalar(AnchorName.Empty, TagName.Empty, bigInt.ToString(), ScalarStyle.Plain, true, false));
                }
            }
            else if (item is DateTime dateTime) {
                // If emitTags is enabled, infer tag from type
                if (emitTags) {
                    var tag = GetTagFromType(item);
                    emitter.Emit(new Scalar(AnchorName.Empty, tag, dateTime.ToString("o"), ScalarStyle.Any, false, false));
                } else {
                    emitter.Emit(new Scalar(AnchorName.Empty, TagName.Empty, dateTime.ToString("o"), ScalarStyle.Any, true, false));
                }
            }
            else {
                // If emitTags is enabled, infer tag from type
                if (emitTags) {
                    var tag = GetTagFromType(item);
                    if (!string.IsNullOrEmpty(tag)) {
                        emitter.Emit(new Scalar(AnchorName.Empty, tag, item.ToString(), ScalarStyle.Any, false, false));
                    } else {
                        emitter.Emit(new Scalar(item.ToString()));
                    }
                } else {
                    emitter.Emit(new Scalar(item.ToString()));
                }
            }
        }

        emitter.Emit(new SequenceEnd());
    }
}
