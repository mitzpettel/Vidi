//
//  NSDictionary-DBVidiJobAdditions.h
//  Vidi
//
//  Created by Mitz Pettel on Tue Feb 25 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DBTVChannel;

#define DBVidiJobChannelKey			@"channel"
#define DBVidiJobSchedStartDateKey		@"scheduled start date"
#define DBVidiJobSchedEndDateKey		@"scheduled end date"
#define DBVidiJobSchedFileKey			@"scheduled file"
#define DBVidiJobActualStartDateKey		@"actual start date"
#define DBVidiJobActualEndDateKey		@"actual end date"
#define DBVidiJobActualFileKey			@"actual file"
#define DBVidiJobCommentsKey			@"comments"
#define DBVidiJobStatusKey			@"status"
#define DBVidiJobIsPermanentKey			@"is permanent"
#define DBVidiJobChunkSizeKey			@"chunk size"
#define DBVidiJobRecurrenceKey			@"recurrence"
#define DBVidiJobOverwriteKey			@"overwrite"

#define DBVidiJobIsAudioKey			@"is audio"
#define DBVidiJobAudioSampleRateKey		@"audio sample rate"
#define DBVidiJobAudioSampleSizeKey		@"audio sample size"
#define DBVidiJobAudioChannelsKey		@"audio channels"
#define DBVidiJobAudioCompressionKey		@"audio compression"
#define DBVidiJobAudioCompressionParamsKey	@"audio compression parameters"

#define DBVidiJobStatusUnscheduled		@"unscheduled"
#define DBVidiJobStatusScheduled		@"scheduled"
#define DBVidiJobStatusActive			@"active"
#define DBVidiJobStatusCompleted		@"completed"
#define DBVidiJobStatusAbended			@"abended"

@interface NSDictionary (DBVidiJobAdditions)

+ (id)vidiJobWithStartDate:(NSCalendarDate *)start endDate:(NSCalendarDate *)end channel:(DBTVChannel *)channel file:(NSString *)path comments:(NSString *)comments permanent:(BOOL)flag;
- (DBTVChannel *)channel;
- (NSCalendarDate *)scheduledStartDate;
- (NSCalendarDate *)scheduledEndDate;
- (NSString *)scheduledFile;
- (NSDate *)actualStartDate;
- (NSDate *)actualEndDate;
- (NSString *)actualFile;
- (NSString *)status;
- (BOOL)isPermanent;
- (unsigned long)chunkSize;
- (int)recurrence;
- (BOOL)overwrite;

- (BOOL)isAudio;
- (UnsignedFixed)audioSampleRate;
- (int)audioSampleSize;
- (int)audioChannels;
- (OSType)audioCompression;
- (NSData *)audioCompressionParameters;

- (NSComparisonResult)compareToVidiJob:(NSDictionary *)otherJob;

@end
