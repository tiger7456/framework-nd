#!/usr/bin/perl 

my $msgDefFile = shift;
my $msgOutFile = $msgDefFile;
$msgOutFile =~ s/msg$/h/;

my %msgName2Type;
my @submsgName2Type;

#hash table for all the message defination
#structure
#msgName=>[(FieldName, FieldType, M/O)]
my %msgsDef;
my @msgsSeq;
my %submsgsDef;

#load defination
parseMsgDef();

dumpMsgDef();

#print message
open CMSG_HANDLE, " > $msgOutFile" or die "failed to open $msgOutFile:$!\n";

    genHeaders();

    foreach my $TypeLenTypeValue (@submsgName2Type)
    {
        (my $subType, my $lengthType, my $subValue) = @$TypeLenTypeValue;
        genSubMsg($subType, $lengthType, $subValue);
    }
    foreach my $msgName  (@msgsSeq)
    {
        genMsg($msgName, $msgsDef{$msgName});
    }

    genEnd();
    #genRootMsg();
close CMSG_HANDLE;

genLuaParser();

exit 0;
################################################################################
#######################       generate LuaParser  ##############################
################################################################################
sub genLuaParser
{
    my $protocolName = "Msg";
    my $luaOutFile = "$protocolName.lua";

    open LUAPARSER_HANDLE, " > $luaOutFile" or die "failed to open $luaOutFile:$!\n";

    ################################################################################
    #define protocol
    ################################################################################
print LUAPARSER_HANDLE <<END_OF_HEADER;
do
    local p_${protocolName} = Proto("${protocolName}", "${protocolName}")

    local f_Tlv = ProtoField.bytes{"${protocolName}.Tlv", "Tlv"}
    local f_TlvTag = ProtoField.uint8{"${protocolName}.TlvTag", "TlvTag", base.DEC}
    local f_TlvLenUint8 = ProtoField.uint8{"${protocolName}.TlvLenUint8", "TlvLenUint8", base.DEC}
    local f_TlvLenUint16 = ProtoField.uint16{"${protocolName}.TlvLenUint16", "TlvLenUint16", base.DEC}
    local f_TlvLenUint32 = ProtoField.uint32{"${protocolName}.TlvLenUint32", "TlvLenUint32", base.DEC}
    local f_TlvLenUint64 = ProtoField.uint64{"${protocolName}.TlvLenUint64", "TlvLenUint64", base.DEC}
    local f_TlvString = ProtoField.bytes{"${protocolName}.TlvString", "TlvString"}
    local f_unknow = ProtoField.bytes("${protocolName}.unknow","unknow")
END_OF_HEADER

    ################################################################################
    #define protocol field
    ################################################################################
    my %definedFields;
    foreach my $msgName (@msgsSeq)
    {
        my $msgDef = $msgsDef{$msgName};
print LUAPARSER_HANDLE <<EOF_INT_FIELD_DEF;

    --${msgName}
EOF_INT_FIELD_DEF
        foreach(@$msgDef)
        {
            ($fieldName, $fieldType, $fieldOption) = @$_;
            my $comment = '--' if $definedFields{"f_$fieldName"}; 
            $definedFields{"f_$fieldName"} = 1;
            if ($fieldType =~ /^(Uint|Length|MsgId)(\d+)/)
            {
                my $intLen = $2;
print LUAPARSER_HANDLE <<EOF_INT_FIELD_DEF;
    ${comment}local f_${fieldName} = ProtoField.uint${intLen}{"${protocolName}.${fieldName}", "${fieldName}", base.DEC}
EOF_INT_FIELD_DEF
            }
            elsif ($fieldType =~ /^PlainString/)
            {
print LUAPARSER_HANDLE <<EOF_INT_FIELD_DEF;
    ${comment}local f_${fieldName} = ProtoField.string{"${protocolName}.${fieldName}", "${fieldName}"}
EOF_INT_FIELD_DEF
            }
        }
    }
    my $luaFields = join ", ", keys(%definedFields);
print LUAPARSER_HANDLE <<EOF_INT_FIELD_DEF;
    p_${protocolName}.fields = { ${luaFields}, f_TlvTag, f_TlvLenUint8, f_TlvLenUint16, f_TlvLenUint32, f_TlvLenUint64, f_TlvString, f_unknow}

    local data_dis = Dissector.get("data")

EOF_INT_FIELD_DEF

    ################################################################################
    # gen Tlv dissector
    ################################################################################
    foreach my $tlvLen (1, 2, 4, 8)
    {
        my $lenType = "TlvLenUint" . ($tlvLen * 8);
print LUAPARSER_HANDLE <<EOF_TLV_DISSECTOR;
    local function Tlv_${lenType}_dissector(buf, offset, endoffset, pkt, t)
        local submsglen = 0
        if (offset + 1 <= endoffset) then
            t:add(f_TlvTag, buf(offset, 1))
            offset = offset + 1
        else
            t:add(f_unknow, buf(offset, endoffset - offset))
            offset = endoffset
            return offset
        end
        if (offset + ${tlvLen} <= endoffset) then
            t:add(f_${lenType}, buf(offset, ${tlvLen}))
            submsglen =  buf(offset, ${tlvLen}):uint()
            offset = offset + ${tlvLen}
        else
            t:add(f_unknow, buf(offset, endoffset - offset))
            offset = endoffset
            return offset
        end
        if (submsglen == 0) then
            return offset
        end
        if (offset + submsglen <= endoffset) then
            t:add(f_TlvString, buf(offset, submsglen))
            offset = offset + submsglen
        else
            t:add(f_unknow, buf(offset, endoffset - offset))
            offset = endoffset
            return offset
        end

        return offset
    end    
EOF_TLV_DISSECTOR
    }
    ################################################################################
    # gen Tlv sub msg dissector
    ################################################################################
print LUAPARSER_HANDLE <<EOF_TLV_SUBMSG_DISSECTOR;

    local function Tlv_SubMsg_dissector(buf, offset, endoffset, pkt, t)
        local tag = 0
        while offset < endoffset do
            if (offset + 1 <= endoffset) then
                tag = buf(offset, 1):uint()
            else
                return offset
            end
EOF_TLV_SUBMSG_DISSECTOR
    my $else;
    foreach my $TypeLenTypeValue (@submsgName2Type)
    {
        (my $subType, my $lengthType, my $subValue) = @$TypeLenTypeValue;
        #print "TlvString<$subValue, $lengthType> $subType\n";
        my $lengthBytes = $lengthType;
        $lengthBytes =~ s/\D//g;
        $lengthBytes /= 8;
print LUAPARSER_HANDLE <<EOF_TLV_SUBMSG_DISSECTOR;
            ${else}if (${subValue} == tag) then
                local submsglen = 0
                if (offset + ${lengthBytes} <= endoffset) then
                    submsglen =  buf(offset, ${lengthBytes}):uint()
                else
                    t:add(f_unknow, buf(offset, endoffset - offset))
                    offset = endoffset
                    return offset
                end
                subtree = t:add(f_Tlv, buf(offset, offset + 1 +  ${lengthBytes} + submsglen))
                subtree:append_text("${subType}")
                offset = Tlv_TlvLen${lengthType}_dissector(buf, offset, endoffset, pkt, subtree)
EOF_TLV_SUBMSG_DISSECTOR
            $else = "else"
    }
print LUAPARSER_HANDLE <<EOF_TLV_SUBMSG_DISSECTOR;
            else
                t:add(f_unknow, buf(offset, endoffset - offset))
                offset = endoffset
                return offset
            end
        end
    end
EOF_TLV_SUBMSG_DISSECTOR

    close LUAPARSER_HANDLE;

}

################################################################################
#######################       generate C++        ##############################
################################################################################
sub genHeaders
{
print CMSG_HANDLE<<END_OF_HEADER;
// this file is generate automatically, please don't change it mannually
#ifndef MESSAGE_H
#define MESSAGE_H

#include "StrMsg.h"
#include "IntMsg.h"
#include "Log.h"
#include <boost/optional.hpp>

namespace Msg
{

END_OF_HEADER
}

sub genEnd
{
print CMSG_HANDLE<<END_OF_MESSAGE_E;
}

#endif /* MESSAGE_H */

END_OF_MESSAGE_E
}
################################################################################
#######################       generate genSubMsg       #######################
################################################################################
sub genSubMsg
{
    my $submsgType = shift;
    my $submsgLenType = shift;
    my $submsgValue = shift;

print CMSG_HANDLE<<END_OF_SUBMSG;
    typedef TlvString<${submsgValue}, ${submsgLenType}> ${submsgType};
END_OF_SUBMSG

}

################################################################################
#######################       generate genMsg       #######################
################################################################################
sub genMsg
{
    my $msgName = shift;
    my $msgDef = shift;
    
print CMSG_HANDLE<<END_OF_MSGDEF_CLASS_B;

    class ${msgName}
    {
    public:
        ${msgName}(){}
        ~${msgName}(){}

END_OF_MSGDEF_CLASS_B
    my $msgType = $msgName2Type{$msgName};
    if ($msgType)
    {
print CMSG_HANDLE<<END_OF_MSGDEF_ENUM;
        enum{ ID = ${msgType}};

END_OF_MSGDEF_ENUM

    }
    genMinSize($msgName, $msgDef);

    genInitFunction($msgName, $msgDef);
    genDecodeFunction($msgName, $msgDef);
    genEncodeFunction($msgName, $msgDef);
    genDumpFunction($msgName, $msgDef);
    genFieldDef($msgName, $msgDef);

print CMSG_HANDLE<<END_OF_MSGDEF_CLASS_E;
    }; /* end of class ${msgName} */

END_OF_MSGDEF_CLASS_E
}
################################################################################
sub genMinSize
{
    my $msgName = shift;
    my $msgDef = shift;

print CMSG_HANDLE<<END_OF_MINSIZE_BEG;
        enum
        {
            MIN_BYTES =
END_OF_MINSIZE_BEG
    
    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldOption eq "M")
        {
print  CMSG_HANDLE<<END_OF_MINSIZE_BODY;
                        ${fieldType}::MIN_BYTES +
END_OF_MINSIZE_BODY
        }

    }

print CMSG_HANDLE <<END_OF_MINSIZE_END;
                        0
        }; /* end of enum MIN_BYTES */

END_OF_MINSIZE_END


}
################################################################################
sub genDumpFunction
{
    my $msgName = shift;
    my $msgDef = shift;

print CMSG_HANDLE<<END_OF_DUMP_BEG;
        template<typename StreamType>
        StreamType& dump(StreamType& theOut, unsigned theLayer = 0)
        {
            std::string leadStr(theLayer * 4, ' ');
            theOut << "\\n" <<leadStr << "${msgName}";
            leadStr.append("    ");
END_OF_DUMP_BEG
    
    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldOption eq "M")
        {
print  CMSG_HANDLE<<END_OF_DUMP_BODY;

            theOut << "\\n" << leadStr << "${fieldName}: ";
            $fieldName.dump(theOut, theLayer + 1);

END_OF_DUMP_BODY
        }
        elsif ($fieldOption eq "O")
        {
print  CMSG_HANDLE<<END_OF_DUMP_OBODY;
            if (${fieldName})
            {
                theOut << "\\n" << leadStr << "${fieldName}: ";
                $fieldName->dump(theOut, theLayer + 1);           
            }
END_OF_DUMP_OBODY

        }

    }

print CMSG_HANDLE <<END_OF_DUMP_END;
            if (0 == theLayer)
            {
                theOut << "\\n";
            }
            return theOut;
        } /* end of dump(...) */

END_OF_DUMP_END


}
################################################################################
sub genFieldDef
{
    my $msgName = shift;
    my $msgDef = shift;

print CMSG_HANDLE<<END_OF_MSGFIELD_B;

    public:
END_OF_MSGFIELD_B

    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldOption eq "M")
        {
print  CMSG_HANDLE<<END_OF_FIELDDEF_BODY;
        ${fieldType} ${fieldName};           
END_OF_FIELDDEF_BODY
        }
        elsif ($fieldOption eq "O")
        {
print  CMSG_HANDLE<<END_OF_FIELDDEF_OBODY;
        boost::optional<${fieldType}> ${fieldName};           
END_OF_FIELDDEF_OBODY
        }
        else
        {
            die "invalid Optional Definination for $msgName.$fieldName";
        }
    }

}
################################################################################
sub genInitFunction
{
    my $msgName = shift;
    my $msgDef = shift;

print CMSG_HANDLE<<END_OF_INIT_BEG;
        void init()
        {
END_OF_INIT_BEG
    
    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldOption eq "M")
        {
print  CMSG_HANDLE<<END_OF_INIT_BODY;
            ${fieldName}.init();            
END_OF_INIT_BODY
        }
    }

print CMSG_HANDLE <<END_OF_INIT_END;
        } /* end of void init(...) */

END_OF_INIT_END

}

################################################################################
sub genDecodeFunction
{
    my $msgName = shift;
    my $msgDef = shift;
    my $theMsg = "the$msgName";
    my $optianlExisted = 0;
    my $msgLengthVar = "theLen";

print CMSG_HANDLE<<END_OF_DECODE_BEG;
        int decode(const char* theBuffer, const unsigned theLen, unsigned& theIndex)
        {
END_OF_DECODE_BEG
    
    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldOption eq "M")
        {
print  CMSG_HANDLE<<END_OF_DECODE_BODY;
            if (0 != ${fieldName}.decode(theBuffer, ${msgLengthVar}, theIndex))            
            {
                LOG_ERROR("failed to parse ${msgName}.${fieldName}");
                return -2;
            }

END_OF_DECODE_BODY
            if ($fieldType =~ /^Length/)
            {
print  CMSG_HANDLE<<END_OF_DECODE_LENGTH;
            unsigned endIndex = theIndex - ${fieldType}::MIN_BYTES + ${fieldName}.valueM;
            if (theLen < endIndex)
            {
                LOG_ERROR("failed to parse ${msgName}.${fieldName}");
                return -2;
            }
END_OF_DECODE_LENGTH
                $msgLengthVar = "endIndex";
            }
           
        }
        elsif ($fieldOption eq "O" && $optianlExisted == 0)
        {
            $optianlExisted = 1;
print  CMSG_HANDLE<<END_OF_DECODE_WOBODY;
            while(theIndex < ${msgLengthVar})
            {
                if (theBuffer[theIndex] == ${fieldType}::TAG) 
                {
                    ${fieldName}.reset(${fieldType}());
                    if (0 != $fieldName->decode( theBuffer, ${msgLengthVar}, theIndex))            
                    {
                        LOG_ERROR("failed to parse ${msgName}.${fieldName}");
                        return -1;
                    }
                }
END_OF_DECODE_WOBODY
        }
        elsif ($fieldOption eq "O")
        {
print  CMSG_HANDLE<<END_OF_DECODE_OBODY;
                else if (theBuffer[theIndex] == ${fieldType}::TAG) 
                {
                    ${fieldName}.reset(${fieldType}());
                    if (0 != $fieldName->decode( theBuffer, ${msgLengthVar}, theIndex))            
                    {
                        LOG_ERROR("failed to parse ${msgName}.${fieldName}");
                        return -1;
                    }
                }
END_OF_DECODE_OBODY

        }

    }
    if ($optianlExisted == 1)
    {
print  CMSG_HANDLE<<END_OF_DECODE_OBODY_E;
                else
                {
                    LOG_ERROR("failed to parse structure at index" << theIndex);
                    return -1;
                }
           } 
END_OF_DECODE_OBODY_E
    }
    if ($msgLengthVar ne "theLen") 
    {
print CMSG_HANDLE <<CHECK_END_OF_DECODE_CHECK_END;
CHECK_END_OF_DECODE_CHECK_END
    }
print CMSG_HANDLE <<END_OF_DECODE_END;

            return 0;
        } /* end of int decode(...) */

END_OF_DECODE_END

}
################################################################################
sub genEncodeFunction
{
    my $msgName = shift;
    my $msgDef = shift;
    my $lenFieldName;
    my $lenFieldType;

print CMSG_HANDLE<<END_OF_ENCODE_BEG;
        int encode(char* theBuffer, const unsigned theLen, unsigned& theIndex)
        {
END_OF_ENCODE_BEG
    
    foreach(@$msgDef)
    {
        ($fieldName, $fieldType, $fieldOption) = @$_;
        if ($fieldType =~ /^Length/)
        {
            $lenFieldName = $fieldName;
            $lenFieldType = $fieldType;
print  CMSG_HANDLE<<END_OF_ENCODE_LEN_B;
            unsigned startIndex = theIndex;
            if (0 != ${fieldName}.encode(theBuffer, theLen, theIndex))            
            {
                LOG_ERROR("failed to encode ${msgName}.${fieldName}");
                return -1;
            }

END_OF_ENCODE_LEN_B
        }
        elsif ($fieldOption eq "M")
        {
            if ($fieldType =~ /^MsgId/)
            {
print  CMSG_HANDLE<<END_OF_ENCODE_SET_ID;
            ${fieldName}.valueM = ${msgName}::ID;
END_OF_ENCODE_SET_ID

            }
print  CMSG_HANDLE<<END_OF_ENCODE_BODY;
            if (0 != ${fieldName}.encode(theBuffer, theLen, theIndex))            
            {
                LOG_ERROR("failed to encode ${msgName}.${fieldName}");
                return -1;
            }

END_OF_ENCODE_BODY
        }
        elsif ($fieldOption eq "O")
        {
print  CMSG_HANDLE<<END_OF_ENCODE_OBODY;
            if ($fieldName) 
            {
                if (0 != $fieldName->encode(theBuffer, theLen, theIndex))            
                {
                    LOG_ERROR("failed to encode ${msgName}.${fieldName}");
                    return -1;
                }
            }
END_OF_ENCODE_OBODY

        }
        else
        {
            die "Please set the Optional Flag for ${msgName}.${fieldName}\n";
        }

    }
    if ($lenFieldName)
    {
print  CMSG_HANDLE<<END_OF_ENCODE_LEN_E;

            //re-encode the length
            ${lenFieldName}.valueM = theIndex - startIndex;
            if (0 != $lenFieldName.encode(theBuffer, theLen, startIndex))            
            {
                LOG_DEBUG("failed to encode ${msgName}.${lenFieldName}");
                return -1;
            }

END_OF_ENCODE_LEN_E

    }

print CMSG_HANDLE <<END_OF_ENCODE_END;
            return 0;
        } /* end of int encode(...) */

END_OF_ENCODE_END

}


################################################################################
#######################       parse message       ##############################
################################################################################
sub parseMsgDef
{
    my $state = "NONE";
    my $curMsg;
    my $lineNo = 0;
    open MSG_DEF_HANDLER, "< $msgDefFile" or die "failed to open $msgDefFile:$!\n";
    while (<MSG_DEF_HANDLER>)
    {
        $lineNo++;
        chomp;
        my $line = $_;
        $line =~ s/\#.*$//g;
        next if $line =~ /^\s*$/;
        
        if ($state eq "MessageList")
        {
            if ($line =~ /^\s+(\w+)\s+(\w+)\s*$/)
            {
                $msgName2Type{$1} = $2;
            }
            else
            {
                $state = "NONE";
            }
        }
        
        if ($state eq "SubMessageList")
        {
            if ($line =~ /^\s+(\w+)\s+(\w+)\s+(\w+)\s*$/)
            {
                push @submsgName2Type, [$1, $2, $3];
            }
            else
            {
                $state = "NONE";
            }
        }

        if ($state eq "Message")
        {
            if ($line =~ /^\s+include\s+(\w+)\s*$/)
            {
                @{$msgsDef{$curMsg}} = (@{$msgsDef{$curMsg}}, @{$submsgsDef{$1}} );
            }
            elsif ($line =~ /^\s+(\w+)\s+(\w+)\s+(\w+)\s*$/)
            {
                push @{$msgsDef{$curMsg}}, [lcfirst($1), $2, $3];
            }
            else
            {
                $state = "NONE";
            }
        }

        if ($state eq "SubMessage")
        {
            if ($line =~ /^\s+include\s+(\w+)\s*$/)
            {
                @{$submsgsDef{$curMsg}} = (@{$submsgsDef{$curMsg}}, @{$submsgsDef{$1}} );
            }
            elsif ($line =~ /^\s+(\w+)\s+(\w+)\s+(\w+)\s*$/)
            {
                push @{$submsgsDef{$curMsg}}, [lcfirst($1), $2, $3];
            }
            else
            {
                $state = "NONE";
            }
        }
        
        if ($state eq "NONE")
        {
            if ($line =~ /^MessageList/)
            {
                $state = "MessageList";
            }
            elsif ($line =~ /^SubMessageList/)
            {
                $state = "SubMessageList";
            }
            elsif ($line =~ /^SubMessage\s+(\w+)\s*$/)
            {
                $curMsg = $1;
                $submsgsDef{$curMsg} = [];
                $state = "SubMessage";
            }
            elsif ($line =~ /^Message\s+(\w+)\s*$/)
            {
                $curMsg = $1;
                $msgsDef{$curMsg} = [];
                $state = "Message";
                push @msgsSeq, $curMsg;
            }
            else
            {
                die "parse error at line: $lineNo:$line\n";
            }
        }
    }

    close MSG_DEF_HANDLER;
}

################################################################################

sub dumpMsgDef
{
    print "-" x 35 . "Message2Type" . "-" x 35 . "\n";
    while(($key, $value) = each %msgName2Type)
    {
        print "$key\t$value\n";
    }

    print "-" x 35 . "SubMessage2Type" . "-" x 35 . "\n";
    foreach my $TypeLenTypeValue (@submsgName2Type)
    {
        (my $subType, my $lengthType, my $subValue) = @$TypeLenTypeValue;
        print "TlvString<$subValue, $lengthType> $subType\n";
    }
    while(($key, $value) = each %submsgName2Type)
    {
        print "$key\t$value\n";
    }

    print "-" x 35 . "SubMessageDef" . "-" x 35 . "\n";
    while(($key, $value) = each %submsgsDef)
    {
        print "$key\n";
        foreach(@$value)
        {
            ($a, $b, $c) = @$_;
            print "\t$a\t$b\t$c\n";
        }
        
    }

    print "-" x 35 . "MessageDef" . "-" x 35 . "\n";
    while(($key, $value) = each %msgsDef)
    {
        print "$key\n";
        foreach(@$value)
        {
            ($a, $b, $c) = @$_;
            print "\t$a\t$b\t$c\n";
        }
        
    }
    
}
