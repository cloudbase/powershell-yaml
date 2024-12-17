using System;
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

public sealed class NullValueGraphVisitor : ChainedObjectGraphVisitor
{
    public NullValueGraphVisitor(IObjectGraphVisitor<IEmitter> nextVisitor)
        : base(nextVisitor)
    {
    }

    public override bool EnterMapping(IPropertyDescriptor key, IObjectDescriptor value, IEmitter context, ObjectSerializer serializer) {
        if (value.Value == null) {
            return false;
        }
        return base.EnterMapping(key, value, context, serializer);
    }

    public override bool EnterMapping(IObjectDescriptor key, IObjectDescriptor value, IEmitter context, ObjectSerializer serializer) {
        if (value.Value == null) {
            return false;
        }
        return base.EnterMapping(key, value, context, serializer);
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

    public IDictionaryTypeConverter(bool omitNullValues = false, bool useFlowStyle = false) {
        this.omitNullValues = omitNullValues;
        this.useFlowStyle = useFlowStyle;
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

        emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, mappingStyle));
        foreach (DictionaryEntry entry in hObj) {
            if(entry.Value == null) {
                if (this.omitNullValues == true) {
                    continue;
                }
                serializer(entry.Key, entry.Key.GetType());
                emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
                continue;
            }
            serializer(entry.Key, entry.Key.GetType());
            var objType = entry.Value.GetType();
            var val = entry.Value;
            if (entry.Value is PSObject nestedObj) {
                var nestedType = nestedObj.BaseObject.GetType();
                if (nestedType != typeof(System.Management.Automation.PSCustomObject)) {
                    objType = nestedObj.BaseObject.GetType();
                    val = nestedObj.BaseObject;
                }
                serializer(val, objType);
            } else {
                serializer(entry.Value, entry.Value.GetType());
            }
        }
        emitter.Emit(new MappingEnd());
    }
}

public class PSObjectTypeConverter : IYamlTypeConverter {

    private bool omitNullValues;
    private bool useFlowStyle;

    public PSObjectTypeConverter(bool omitNullValues = false, bool useFlowStyle = false) {
        this.omitNullValues = omitNullValues;
        this.useFlowStyle = useFlowStyle;
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
        var mappingStyle = this.useFlowStyle ? MappingStyle.Flow : MappingStyle.Block;
        emitter.Emit(new MappingStart(AnchorName.Empty, TagName.Empty, true, mappingStyle));
        foreach (var prop in psObj.Properties) {
            if (prop.Value == null) {
                if (this.omitNullValues == true) {
                    continue;
                }
                serializer(prop.Name, prop.Name.GetType());
                emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
            } else {
                serializer(prop.Name, prop.Name.GetType());
                var objType = prop.Value.GetType();
                var val = prop.Value;
                if (prop.Value is PSObject nestedPsObj) {
                    var nestedType = nestedPsObj.BaseObject.GetType();
                    if (nestedType != typeof(System.Management.Automation.PSCustomObject)) {
                        objType = nestedPsObj.BaseObject.GetType();
                        val = nestedPsObj.BaseObject;
                    }
                }
                serializer(val, objType);

            }
        }
        emitter.Emit(new MappingEnd());
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

public class FlowStyleAllEmitter: ChainedEventEmitter {
    public FlowStyleAllEmitter(IEventEmitter next): base(next) {}

    public override void Emit(MappingStartEventInfo eventInfo, IEmitter emitter) {
        eventInfo.Style = MappingStyle.Flow;
        base.Emit(eventInfo, emitter);
    }

    public override void Emit(SequenceStartEventInfo eventInfo, IEmitter emitter){
        eventInfo.Style = SequenceStyle.Flow;
        nextEmitter.Emit(eventInfo, emitter);
    }
}

public class FlowStyleSequenceEmitter: ChainedEventEmitter {
    public FlowStyleSequenceEmitter(IEventEmitter next): base(next) {}

    public override void Emit(SequenceStartEventInfo eventInfo, IEmitter emitter){
        eventInfo.Style = SequenceStyle.Flow;
        nextEmitter.Emit(eventInfo, emitter);
    }
}

class BuilderUtils {
    public static SerializerBuilder BuildSerializer(
        SerializerBuilder builder,
        bool omitNullValues = false,
        bool useFlowStyle = false,
        bool useSequenceFlowStyle = false,
        bool jsonCompatible = false) {

        if (jsonCompatible == true) {
            useFlowStyle = true;
            useSequenceFlowStyle = true;
        }

        builder = builder
            .WithEventEmitter(next => new StringQuotingEmitter(next))
            .WithTypeConverter(new BigIntegerTypeConverter())
            .WithTypeConverter(new IDictionaryTypeConverter(omitNullValues, useFlowStyle))
            .WithTypeConverter(new PSObjectTypeConverter(omitNullValues, useFlowStyle));
        if (omitNullValues == true) {
            builder = builder
                .WithEmissionPhaseObjectGraphVisitor(args => new NullValueGraphVisitor(args.InnerVisitor));
        }
        if (useFlowStyle == true) {
            builder = builder.WithEventEmitter(next => new FlowStyleAllEmitter(next));
        }
        if (useSequenceFlowStyle == true) {
            builder = builder.WithEventEmitter(next => new FlowStyleSequenceEmitter(next));
        }

        return builder;
    }
}
