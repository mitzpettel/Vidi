//
//  NSDictionary-DBVidiJobAdditions.m
//  Vidi
//
//  Created by Mitz Pettel on Tue Feb 25 2003.
//  Copyright (c) 2003, 2007 Mitz Pettel. All rights reserved.
//

#import "NSDictionary-DBVidiJobAdditions.h"

#import "DBTVChannel.h"

@implementation NSDictionary (DBVidiJobAdditions)

+ (id)vidiJobWithStartDate:(NSCalendarDate *)start endDate:(NSCalendarDate *)end channel:(DBTVChannel *)channel file:(NSString *)path comments:(NSString *)comments permanent:(BOOL)flag
{
    return [self dictionaryWithObjectsAndKeys:
        start, DBVidiJobSchedStartDateKey,
        end, DBVidiJobSchedEndDateKey,
        [channel dictionary], DBVidiJobChannelKey,
        path, DBVidiJobSchedFileKey,
        comments, DBVidiJobCommentsKey,
        DBVidiJobStatusUnscheduled, DBVidiJobStatusKey,
        [NSNumber numberWithBool:flag], DBVidiJobIsPermanentKey,
        nil
    ];
}

- (DBTVChannel *)channel
{
    return [DBTVChannel channelWithDictionary:[self objectForKey:DBVidiJobChannelKey]];
}

- (NSCalendarDate *)scheduledStartDate
{
    id result = [self objectForKey:DBVidiJobSchedStartDateKey];
    if (result != nil && ![result isKindOfClass:[NSCalendarDate class]])
        result = [[[NSCalendarDate alloc] initWithTimeInterval:0 sinceDate:result] autorelease];
    return result;
}

- (NSCalendarDate *)scheduledEndDate
{
    id result = [self objectForKey:DBVidiJobSchedEndDateKey];
    if (result != nil && ![result isKindOfClass:[NSCalendarDate class]])
        result = [[[NSCalendarDate alloc] initWithTimeInterval:0 sinceDate:result] autorelease];
    return result;
}

- (NSString *)scheduledFile
{
    return [self objectForKey:DBVidiJobSchedFileKey];
}

- (NSDate *)actualStartDate
{
    return [self objectForKey:DBVidiJobActualStartDateKey];
}

- (NSDate *)actualEndDate
{
    return [self objectForKey:DBVidiJobActualEndDateKey];
}

- (NSString *)actualFile
{
    return [self objectForKey:DBVidiJobActualFileKey];
}

- (NSString *)status
{
    return [self objectForKey:DBVidiJobStatusKey];
}

- (BOOL)isPermanent
{
    return [[self objectForKey:DBVidiJobIsPermanentKey] boolValue];
}

- (unsigned long)chunkSize
{
    return [[self objectForKey:DBVidiJobChunkSizeKey] unsignedLongValue];
}

- (int)recurrence
{
    return [[self objectForKey:DBVidiJobRecurrenceKey] intValue];
}

- (BOOL)overwrite
{
    return [[self objectForKey:DBVidiJobOverwriteKey] boolValue];
}

- (BOOL)isAudio
{
    return [[self objectForKey:DBVidiJobIsAudioKey] boolValue];
}

- (UnsignedFixed)audioSampleRate
{
    return [[self objectForKey:DBVidiJobAudioSampleRateKey] unsignedLongValue];
}

- (int)audioSampleSize
{
    return [[self objectForKey:DBVidiJobAudioSampleSizeKey] intValue];
}

- (int)audioChannels
{
    return [[self objectForKey:DBVidiJobAudioChannelsKey] intValue];
}

- (OSType)audioCompression
{
    return [[self objectForKey:DBVidiJobAudioCompressionKey] unsignedLongValue];
}

- (NSData *)audioCompressionParameters
{
    return [self objectForKey:DBVidiJobAudioCompressionParamsKey];
}

- (NSComparisonResult)compareToVidiJob:(NSDictionary *)otherJob
{
    return [[self scheduledStartDate] compare:[otherJob scheduledStartDate]];
}

@end
