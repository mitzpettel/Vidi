//
//  DBTVChannel.m
//  Vidi
//
//  Created by Mitz Pettel on Sun Jan 26 2003.
//  Copyright (c) 2002, 2003 Mitz Pettel. All rights reserved.
//

#import "DBTVChannel.h"


NSString * const DBTVFrequencyKey = @"frequency";
NSString * const DBTVNameKey = @"name";
NSString * const DBTVVolumeKey = @"volume";
NSString * const DBTVLogoKey = @"logo";
NSString * const DBTVInputSourceKey = @"input source";

NSString * const DBTVChannelChangedNotification = @"DBTVChannelChangedNotification";

@implementation DBTVChannel

+ (id)channelWithFrequency:(DBTVFrequency)freq inputSource:(DBDVInputSource)source name:(NSString *)string volume:(float)vol logo:(NSImage *)image
{
    return [[[self alloc] initWithFrequency:freq inputSource:source name:string volume:vol logo:image] autorelease];
}

+ (id)channelWithFrequency:(DBTVFrequency)freq
{
    return [[[self alloc] initWithFrequency:freq] autorelease];
}

+ (id)channelWithDictionary:(NSDictionary *)dict
{
    return [[[self alloc] initWithDictionary:dict] autorelease];
}

- (id)initWithFrequency:(DBTVFrequency)freq inputSource:(DBDVInputSource)source name:(NSString *)string volume:(float)vol logo:(NSImage *)image
{
    self = [super init];
    if (self) {
        _frequency = freq;
        _name = [string retain];
        _volume = vol;
        _logo = [image retain];
        _inputSource = source;
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_logo release];
    [super dealloc];
}

- (id)initWithFrequency:(DBTVFrequency)freq
{
    return [self initWithFrequency:freq inputSource:DBTunerInput name:@"" volume:1.0 logo:NULL];
}

- (id)initWithDictionary:(NSDictionary *)dict
{
    [self initWithFrequency:[[dict objectForKey:DBTVFrequencyKey] floatValue] inputSource:[[dict objectForKey:DBTVInputSourceKey] intValue] name:[dict objectForKey:DBTVNameKey] volume:[[dict objectForKey:DBTVVolumeKey] floatValue] logo:[[[NSImage alloc] initWithData:[dict objectForKey:DBTVLogoKey]] autorelease]];
    return self;
}

- (NSDictionary *)dictionary
{
    NSMutableDictionary *result;
    result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithFloat:[self frequency]], DBTVFrequencyKey,
        [self name], DBTVNameKey,
        [NSNumber numberWithFloat:[self volume]], DBTVVolumeKey,
        [NSNumber numberWithInt:[self inputSource]], DBTVInputSourceKey,
        nil
    ];
    if ([self logo])
        [result setObject:[[self logo] TIFFRepresentation] forKey:DBTVLogoKey];
    return result;
}

- (NSDictionary *)dictionaryWithoutLogo
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithFloat:[self frequency]], DBTVFrequencyKey,
        [self name], DBTVNameKey,
        [NSNumber numberWithFloat:[self volume]], DBTVVolumeKey,
        [NSNumber numberWithInt:[self inputSource]], DBTVInputSourceKey,
        nil
    ];
}

- (void)setFrequency:(DBTVFrequency)freq
{
    _frequency = freq;
    [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:DBTVChannelChangedNotification object:self] postingStyle:NSPostASAP coalesceMask:NSNotificationCoalescingOnSender forModes:nil]; 
}

- (DBTVFrequency)frequency
{
    return _frequency;
}

- (void)setName:(NSString *)string
{
    [_name autorelease];
    _name = [string retain];
    [self _sendChangeNotification];
}

- (NSString *)name
{
    return _name;
}

- (void)setVolume:(float)vol
{
    _volume = vol;
    [self _sendChangeNotification];
}

- (float)volume
{
    return _volume;
}

- (void)setInputSource:(DBDVInputSource)source
{
    _inputSource = source;
    [self _sendChangeNotification];
}

- (DBDVInputSource)inputSource
{
    return _inputSource;
}

- (void)setLogo:(NSImage *)image
{
    [_logo autorelease];
    _logo = [image retain];
    [self _sendChangeNotification];
}

- (NSImage *)logo
{
    return _logo;
}

- (void)_sendChangeNotification
{
    [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:DBTVChannelChangedNotification object:self] postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnSender forModes:nil]; 
}

@end
