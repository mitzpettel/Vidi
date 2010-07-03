//
//  DBVidiServer.h
//  Vidi
//
//  Created by Mitz Pettel on Fri Feb 21 2003.
//  Copyright (c) 2003, 2005 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>


#define DBVidiServerStartedNotification @"DBVidiServerStartedNotification"
#define DBVidiServerName @"com.mitzpettel.Vidi.server"
#define DBShowStatusItemSettingName @"show global menu"
#define DBBrightnessSettingName @"brightness"
#define DBContrastSettingName @"contrast"
#define DBSaturationSettingName @"saturation"
#define DBHueSettingName @"hue"
#define DBJobsKey @"jobs"
#define DBTVChannelsKey @"channels"
#define DBRadioChannelsKey @"radio stations"
#define DBTVChannelSettingName @"channel"
#define DBRadioChannelSettingName @"radio station"
#define DBMoviesDirectorySettingName @"movies directory"
#define DBCallKeysKey @"call keys"
#define DBMegabytesToReserveSettingName @"megabytes to reserve"

@class DBDVGrabber;
@class DBVidiPaletteController;

@protocol DBVidiClient

- (void)serverDidStartJob:(NSDictionary *)job;
- (void)serverDidFinishJob:(NSDictionary *)job;
- (void)serverDidAbendJob:(NSDictionary *)job;
- (void)serverDidUpdateJobs;
- (void)serverDidChangeStatusOfSelectedJob;

@end

@protocol DBVidiServer

- (UInt32)bundleVersion;
- (BOOL)isStatusItemActive;
- (void)setStatusItemActive:(BOOL)flag;
- (DBDVGrabber *)grabber;
- (oneway void)die;
- (BOOL)setClient:(id <DBVidiClient>)client;
- (void)showPalette:(id)sender;
- (BOOL)hasDevice;
- (BOOL)hasRadioTuner;
- (void)setChannelDictionary:(NSDictionary *)dict;
- (void)setChannelDictionary:(NSDictionary *)dict squelch:(BOOL)squelch repeat:(BOOL)repeat;
- (void)addToLoginItems;
- (void)addJob:(NSDictionary *)job;
- (void)selectJobAtIndex:(int)i;
- (NSDictionary *)selectedJob;
- (void)replaceSelectedJobWith:(NSDictionary *)job;
- (NSDictionary *)activeJob;
- (void)removeJobAtIndex:(int)i;
- (void)stopActiveJob;
- (void)setActiveJobEndDate:(NSCalendarDate *)date;
- (NSMutableArray *)jobs;

@end

@interface DBVidiServer : NSObject <DBVidiServer> {
    DBDVGrabber *_grabber;
    NSConnection *_connection;
    NSStatusItem *_statusItem;
    NSMenu *_statusItemMenu;
    BOOL _statusItemActive;
    NSDistantObject <DBVidiClient> *_client;
    DBVidiPaletteController *_paletteController;
    NSMutableArray *_jobs;
    NSMutableDictionary *_activeJob;
    NSMutableDictionary *_selectedJob;
    int _chunkNumber;
    NSTimer *_jobScanTimer;
    BOOL _needsRescan;
    NSTimer *_diskSpaceCheckTimer;
}

- (void)addToLoginItems;
- (void)clientConnectionDied:(NSNotification *)deathNotification;
- (DBDVGrabber *)grabber;
- (void)openVidi:(id)sender;
- (NSImage *)statusImage;
- (void)statusItemAction:(id)sender;
- (void)updateStatusItem;
- (void)scanJobs;
- (void)startJob:(NSMutableDictionary *)job;
- (void)rescheduleJob:(NSMutableDictionary *)job;
- (void)endActiveJob;
- (void)endActiveJobNormally:(BOOL)normal;
- (BOOL)startRecordingToFile:(NSString *)path;
- (void)stopRecording;

@end
