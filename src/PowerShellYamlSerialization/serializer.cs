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

public class PSObjectTypeConverter : IYamlTypeConverter {

    private bool omitNullValues;

    public PSObjectTypeConverter(bool omitNullValues = false) {
        this.omitNullValues = omitNullValues;
    }

    public bool Accepts(Type type) {
        return typeof(PSObject).IsAssignableFrom(type);
    }

    public object ReadYaml(IParser parser, Type type, ObjectDeserializer rootDeserializer)
    {
        var psObject = new PSObject();
        parser.Consume<MappingStart>();

        while (parser.TryConsume<Scalar>(out var scalar)) {
            var key = scalar.Value;
            var value = rootDeserializer(typeof(object));
            psObject.Properties.Add(new PSNoteProperty(key, value));
        }
        parser.Consume<MappingEnd>();
        return psObject;
    }

    public void WriteYaml(IEmitter emitter, object value, Type type, ObjectSerializer serializer) {
        var psObj = (PSObject)value;

        emitter.Emit(new MappingStart());
        foreach (var prop in psObj.Properties) {
            if (prop.Value == null) {
                if (this.omitNullValues == true) {
                    continue;
                }
                serializer(prop.Name, prop.Name.GetType());
                emitter.Emit(new Scalar(AnchorName.Empty, "tag:yaml.org,2002:null", "", ScalarStyle.Plain, true, false));
            } else {
                serializer(prop.Name, prop.Name.GetType());
                serializer(prop.Value, prop.Value.GetType());
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

class BuilderUtils {
    public static SerializerBuilder BuildSerializer(SerializerBuilder builder, bool omitNullValues = false) {
        builder = builder
            .WithEventEmitter(next => new StringQuotingEmitter(next))
            .WithTypeConverter(new BigIntegerTypeConverter())
            .WithTypeConverter(new PSObjectTypeConverter(omitNullValues));
        if (omitNullValues == true) {
            builder = builder
                .WithEmissionPhaseObjectGraphVisitor(args => new NullValueGraphVisitor(args.InnerVisitor));
        }
        return builder;
    }

    public static DeserializerBuilder BuildDeserializer(DeserializerBuilder builder) {
        builder = builder
            .WithTypeConverter(new BigIntegerTypeConverter())
            .WithTypeConverter(new PSObjectTypeConverter(false));
        Console.WriteLine(builder);
        return builder;
    }

}