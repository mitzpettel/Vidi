//
//  DBAudioCompression.m
//  Vidi
//
//  Created by Mitz Pettel on Sat Jul 26 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBAudioCompression.h"
#import "NSDictionary-DBVidiJobAdditions.h"
#import <QuickTime/QuickTimeComponents.h>

@implementation DBAudioCompression

+ (NSDictionary *)runStandardSoundCompressionDialogWithFormat:(NSDictionary *)initialFormat
{
    ComponentInstance	stdComp = OpenDefaultComponent( StandardCompressionType, StandardCompressionSubTypeSound );
    NSMutableDictionary	*result = nil;
    OSStatus		err;
    OSType		compressionType;
    short		numChannels;
    short		sampleSize;
    UnsignedFixed	sampleRate;
    Handle		params;

    if ( initialFormat )
    {
        compressionType = [initialFormat audioCompression];
        if ( compressionType==k16BitBigEndianFormat || compressionType==kSoundNotCompressed )
            compressionType = k8BitOffsetBinaryFormat;
        err = SCSetInfo( stdComp, scSoundCompressionType, &compressionType );
        
        numChannels = [initialFormat audioChannels];
        err = SCSetInfo( stdComp, scSoundChannelCountType, &numChannels );
        
        sampleSize = [initialFormat audioSampleSize];
        err = SCSetInfo( stdComp, scSoundSampleSizeType, &sampleSize );
        
        sampleRate = [initialFormat audioSampleRate];
        err = SCSetInfo( stdComp, scSoundSampleRateType, &sampleRate );
        
        if ( [initialFormat audioCompressionParameters] )
        {
            err = PtrToHand(
                [[initialFormat audioCompressionParameters] bytes],
                &params,
                [[initialFormat audioCompressionParameters] length]
            );
            HLock( params );
            err = SCSetInfo( stdComp, scCodecSettingsType, &params );
            HUnlock( params );
            DisposeHandle( params );
        }
    }

    err = SCRequestImageSettings( stdComp );
    if ( err )
        return nil;
    
    err = SCGetInfo( stdComp, scSoundCompressionType, &compressionType );
    err = SCGetInfo( stdComp, scSoundChannelCountType, &numChannels );
    err = SCGetInfo( stdComp, scSoundSampleSizeType, &sampleSize );
    err = SCGetInfo( stdComp, scSoundSampleRateType, &sampleRate );
    err = SCGetInfo( stdComp, scCodecSettingsType, &params );

    err = CloseComponent( stdComp );
    
    if ( compressionType==k8BitOffsetBinaryFormat ) {
        if ( sampleSize > 8 )
                compressionType = k16BitBigEndianFormat;
        else
                compressionType = kSoundNotCompressed;
    }
    
    result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedLong:sampleRate],	DBVidiJobAudioSampleRateKey,
        [NSNumber numberWithInt:sampleSize],		DBVidiJobAudioSampleSizeKey,
        [NSNumber numberWithInt:numChannels],		DBVidiJobAudioChannelsKey,
        [NSNumber numberWithUnsignedLong:compressionType], DBVidiJobAudioCompressionKey,
        nil
    ];
    
    if ( params )
    {
        HLock( params );
        [result
            setObject:[NSData dataWithBytes:*params length:GetHandleSize( params )]
            forKey:DBVidiJobAudioCompressionParamsKey
        ];
        HUnlock( params );
    }
    
    return result;
}

+ (NSString *)descriptionOfFormat:(NSDictionary *)audioFormat
{
    Str255		compressionNamePStr;
    NSString		*compressionName;
    
    if ( [audioFormat audioCompression]!=kSoundNotCompressed && [audioFormat audioCompression]!=k16BitBigEndianFormat )
    {
        GetCompressionName(
            [audioFormat audioCompression],
            compressionNamePStr
        );
        p2cstrcpy((char *)compressionNamePStr, compressionNamePStr);
        compressionName = [NSString stringWithCString:(char *)compressionNamePStr];
    }
    else
        compressionName = NSLocalizedString( @"Uncompressed", @"uncompressed audio" );
        
    return [NSString
        stringWithFormat:NSLocalizedString( @"%@, %@, %.2f kHz, %d bits", @"audio format string: compression, 'mono' or 'stereo', sample rate, sample size" ),
        compressionName,
        ( [audioFormat audioChannels]==2 ?
            NSLocalizedString( @"Stereo", @"" )
            : NSLocalizedString( @"Mono", @"" )
        ),
        [audioFormat audioSampleRate]/65536000.0,
        [audioFormat audioSampleSize]
    ];
}

@end
