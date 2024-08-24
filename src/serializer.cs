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

public class PSObjectTypeConverter : IYamlTypeConverter {
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

        emitter.Emit(new MappingStart());
        foreach (var prop in psObj.Properties) {
            serializer(prop.Name, prop.Name.GetType());
            serializer(prop.Value, prop.Value.GetType());
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
    // objectGraphVisitor, w => w.OnTop()
    public static SerializerBuilder Add(SerializerBuilder builder) {
        return builder 
            .WithEventEmitter(next => new StringQuotingEmitter(next))
            .WithTypeConverter(new BigIntegerTypeConverter())
            .WithTypeConverter(new PSObjectTypeConverter());
    }
}