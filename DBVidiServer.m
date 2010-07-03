//
//  DBVidiServer.m
//  Vidi
//
//  Created by Mitz Pettel on Fri Feb 21 2003.
//  Copyright (c) 2003, 2004, 2005, 2007 Mitz Pettel. All rights reserved.
//

#import "DBVidiServer.h"

#import "AVCWindowController.h"
#import "DBTVChannel.h"
#import "DBDVGrabber.h"
#import "DBVidiPaletteController.h"
#import "LoginItemAPI.h"
#import "NSDictionary-DBVidiJobAdditions.h"
#import <fcntl.h>


@implementation DBVidiServer

- (id)init
{
    self = [super init];
    if (self)
    {
        _connection = [NSConnection defaultConnection];
        if ( [_connection registerName:DBVidiServerName] )
        {
            [self addToLoginItems];

            [[NSUserDefaults standardUserDefaults]
                registerDefaults:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInt:141],	DBBrightnessSettingName,
                        [NSNumber numberWithInt:60],	DBContrastSettingName,
                        [NSNumber numberWithInt:63],	DBSaturationSettingName,
                        [NSNumber numberWithInt:0],	DBHueSettingName,
                        nil
                    ]
            ];

            _grabber = [DBDVGrabber new];
            [_grabber setDelegate:self];
            [_connection setRootObject:self];
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:DBVidiServerStartedNotification object:nil];
            _paletteController = [[DBVidiPaletteController alloc] initWithServer:self];
            if ([_grabber hasDevice])
                [self grabberDidAcquireDevice:_grabber];
            [self setStatusItemActive:
                [[NSUserDefaults standardUserDefaults]
                    boolForKey:DBShowStatusItemSettingName]
            ];
            _jobs = [NSMutableArray array];
            {
                NSArray *immutableJobs = [[NSUserDefaults standardUserDefaults] objectForKey:DBJobsKey];
                unsigned jobCount = [immutableJobs count];
                unsigned i;
                for ( i = 0; i<jobCount; i++ )
                    [_jobs addObject:[[immutableJobs objectAtIndex:i] mutableCopy]];
            }
            [self scanJobs];
            if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"AVCCommander"] )
            {
                Class controllerClass = NSClassFromString(@"AVCWindowController");
                if ( controllerClass )
                    [[[controllerClass alloc] initWithWindowNibName:@"AVCCommander"] showWindow:nil];
            }
        }
        else
        {
            [self release];
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc
{
    [_client release];
    [_jobScanTimer release];
    [_activeJob release];
    [_jobs release];
    [_paletteController release];
    [_statusItemMenu release];
    [_grabber release];
    [super dealloc];
}

- (void)addToLoginItems
{
    int		itemCount;
    int		i;
    BOOL	added = NO;
    NSString	*ourPath = [[NSBundle mainBundle] bundlePath];
    NSString	*ourName = [ourPath lastPathComponent];
    
    if (!added)
    {
        itemCount = GetCountOfLoginItems(kAllUsers);
        for ( i = 0; i<itemCount; i++ )
        {
            if ([(NSString *)ReturnLoginItemPropertyAtIndex(kAllUsers, kApplicationNameInfo, i)
                isEqual:ourName])
            {
                added = YES;
                break;
            }
        }
    }
    
    if (!added)
    {
        itemCount = GetCountOfLoginItems(kCurrentUser);
        for ( i = 0; i<itemCount; i++ )
        {
            if ([(NSString *)ReturnLoginItemPropertyAtIndex(kCurrentUser, kApplicationNameInfo, i)
                    isEqual:ourName])
            {
                if ([(NSString *)ReturnLoginItemPropertyAtIndex(kCurrentUser, kFullPathInfo, i)
                        isEqual:ourPath])
                    added = YES;
                else
                    RemoveLoginItemAtIndex(kCurrentUser, i);
                break;
            }
        }
    }
    
    if (!added)
        AddLoginItemWithPropertiesToUser(kCurrentUser, (CFStringRef)ourPath, NO);
}

- (UInt32)bundleVersion
{
    return CFBundleGetVersionNumber(CFBundleGetMainBundle());
}

- (void)version044
{
}

- (NSImage *)statusImage
{
    NSImage		*image;
    DBDVGrabber		*grabber = [self grabber];
    BOOL		isTimer = NO;
    NSEnumerator	*jobEnumerator = [[self jobs] objectEnumerator];
    NSDictionary	*job;
    NSString		*status;
    
    while ( !isTimer && ( job = [jobEnumerator nextObject] ) )
    {
        status = [job status];
        if ( ( [status isEqual:DBVidiJobStatusActive] ||
            [status isEqual:DBVidiJobStatusScheduled] ) &&
            ![[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]] )
            isTimer = YES;
    }

    if ([grabber hasDevice])
    {
        if ([grabber isRecording])
        {
            if (_activeJob && isTimer)
                image = [NSImage imageNamed:@"status timer REC"];
            else
                image = [NSImage imageNamed:@"status REC"];
        }
        else if ([grabber isGrabbing] || ![grabber canStartGrabbing])
        {
            if ( isTimer )
                image = [NSImage imageNamed:@"status timer"];
            else
                image = [NSImage imageNamed:@"status"];
        }
        else
        {
            if ( isTimer )
                image = [NSImage imageNamed:@"status timer"];
            else
                image = [NSImage imageNamed:@"status"];
        }
    }
    else
        image = [NSImage imageNamed:@"status problem"];
    return image;
}

- (void)die
{
    [NSApp terminate:nil];
}

- (BOOL)setClient:(id <DBVidiClient>)client;
{
    BOOL	result = NO;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:nil];

    if (client)
    {
        result = [[self grabber] isGrabbing];
        if (!result)
            result = [[self grabber] startGrabbing];
        if (result)
        {
            [[_paletteController window] performClose:nil];
            [[self grabber] setAudioEnabled:YES];
            if ([(NSObject *)client isProxy])
            {
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clientConnectionDied:) name:NSConnectionDidDieNotification object:[(NSDistantObject *)client connectionForProxy]];
            }
        }
    }
    else
    {
        result = YES;
        [[self grabber] setAudioEnabled:NO];
        if ([[self grabber] isGrabbing] && !_activeJob)
            [[self grabber] stopGrabbing];
    }

    if (result)
    {
        [_client autorelease];
        _client = [(NSDistantObject *)client retain];
        _selectedJob = nil;
    }

    return result;
}

- (void)clientConnectionDied:(NSNotification *)deathNotification
{
    if (![[self grabber] isRecording] && [[self grabber] isGrabbing])
        [[self grabber] stopGrabbing];
    [self setClient:nil];
}

- (void)setChannelDictionary:(NSDictionary *)dict
{
    [self setChannelDictionary:dict squelch:NO repeat:YES];
}

- (void)repeatSetFrequency:(NSNumber *)frequency
{
    [[self grabber] setFrequency:[frequency unsignedLongValue]];
}

- (void)setChannelDictionary:(NSDictionary *)dict squelch:(BOOL)squelch repeat:(BOOL)repeat
{
    if ( [[self grabber] firmwareVersion]!=0 )
    {
        DBTVChannel 	*channel = [DBTVChannel channelWithDictionary:dict];
        DBDVInputSource	inputSource = [channel inputSource];
        BOOL		needToChangeSource;
        
        if ( squelch )
            [[self grabber] dropNextFrames:10];
        needToChangeSource = ( inputSource!=[[self grabber] inputSource] );
        if ( needToChangeSource )
            [[self grabber] setInputSource:inputSource];
        if ( inputSource==DBTunerInput )
        {
            [[self grabber] setFrequency:[channel frequency]];
            if ( repeat )
                [self performSelector:@selector(repeatSetFrequency:) withObject:[NSNumber numberWithUnsignedLong:[channel frequency]] afterDelay:0.1];
        }
        if ( inputSource==DBRadioInput )
            [[self grabber] setRadioFrequency:[channel frequency]];
    }
}

- (BOOL)startRecordingToFile:(NSString *)path
{
    DBDVGrabber		*grabber = [self grabber];
    NSFileHandle	*handle;
    NSDictionary	*attributes;
    UInt64		availableBytes;
    
    attributes = [[NSFileManager defaultManager] fileSystemAttributesAtPath:path];
    availableBytes = [[attributes objectForKey:@"NSFileSystemFreeSize"] unsignedLongLongValue];
/*
    if ( availableBytes < 1024*1024*[[NSUserDefaults standardUserDefaults] integerForKey:DBMegabytesToReserveSettingName] )
        return NO;
*/
    if ( ![grabber isGrabbing] )
        return NO;
    if ( [grabber isRecording] )
        return NO;
    if ( ![[NSFileManager defaultManager]
                createFileAtPath:path
                contents:nil
                attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:( [_activeJob isAudio] ? 'AIFC' : 'dvc!' )] forKey:NSFileHFSTypeCode]
            ] )
        return NO;
    // file created
    handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if ( !handle)
        return NO;
    // file open for writing
    _chunkNumber = 0;
    fcntl( [handle fileDescriptor], F_NOCACHE, YES );	// write to disk, don't waste memory on caching
    [grabber setFile:handle];
    [grabber setChunkSize:[_activeJob chunkSize]];
    [grabber
        setAudioRecording:[_activeJob isAudio]
        sampleRate:[_activeJob audioSampleRate]
        sampleSize:[_activeJob audioSampleSize]
        channels:[_activeJob audioChannels]
        compression:[_activeJob audioCompression]
        parameters:[_activeJob audioCompressionParameters]
    ];
    
    [grabber startRecording];
/*
    _diskSpaceCheckTimer = [[NSTimer
        scheduledTimerWithTimeInterval:10
        target:self
        selector:@selector(checkDiskSpace:)
        userInfo:nil
        repeats:YES
    ] retain];
*/
    return YES;
}

/*
- (void)checkDiskSpace:(NSTimer *)timer
{
    NSDictionary	*attributes;
    UInt64		availableBytes;
    NSString		*path;
    
    path = [_activeJob actualFile];
    attributes = [[NSFileManager defaultManager] fileSystemAttributesAtPath:path];
    availableBytes = [[attributes objectForKey:@"NSFileSystemFreeSize"] unsignedLongLongValue];
    if ( availableBytes < 1024*1024*[[NSUserDefaults standardUserDefaults] integerForKey:DBMegabytesToReserveSettingName] )
        [self stopActiveJob];
}
*/

- (NSString *)pathForChunk:(int)chunk
{
    return [NSString
        stringWithFormat:@"%@ (%d).dv",
        [[_activeJob actualFile] stringByDeletingPathExtension],
        chunk
    ];
}

- (void)stopRecording
{
    if ( ![[self grabber] isRecording] )
        return;
/*
    [_diskSpaceCheckTimer invalidate];
    [_diskSpaceCheckTimer release];
*/
    [[self grabber] stopRecording];
    
    // get rid of the empty file if necessary
    if ( [_activeJob chunkSize]!=0 )
        [[NSFileManager defaultManager] removeFileAtPath:[self pathForChunk:_chunkNumber] handler:nil];
}

- (BOOL)hasDevice
{
    return [[self grabber] hasDevice];
}

- (BOOL)hasRadioTuner
{
    return [[self grabber] hasRadioTuner];
}

- (BOOL)isRecording
{
    return [[self grabber] isRecording];
}

- (void)addJob:(NSDictionary *)job
{
    NSMutableDictionary		*newJob = [NSMutableDictionary dictionaryWithDictionary:job];
    [[self jobs] addObject:newJob];
    [newJob setObject:DBVidiJobStatusScheduled forKey:DBVidiJobStatusKey];
    [self scanJobs];
}

- (void)selectJobAtIndex:(int)i
{
    if ( i==-1 )
        _selectedJob = nil;
    else
        _selectedJob = [[self jobs] objectAtIndex:i];
}

- (NSDictionary *)selectedJob
{
    return _selectedJob;
}

- (void)replaceSelectedJobWith:(NSDictionary *)job
{
    if ( _selectedJob )
    {
        id status = [[_selectedJob status] retain];
        id actualFile = [[_selectedJob actualFile] retain];
        id actualStartDate = [[_selectedJob actualStartDate] retain];
        id actualEndDate = [[_selectedJob actualEndDate] retain];
        
        [_selectedJob setDictionary:job];
        
        // actually, we keep most of the stuff as it was:
        [_selectedJob setObject:status forKey:DBVidiJobStatusKey];
        if ( actualFile )
            [_selectedJob setObject:actualFile forKey:DBVidiJobActualFileKey];
        if ( actualStartDate )
            [_selectedJob setObject:actualStartDate forKey:DBVidiJobActualStartDateKey];
        if ( actualEndDate )
            [_selectedJob setObject:actualEndDate forKey:DBVidiJobActualEndDateKey];
        [self scanJobs];

        [status release];
        [actualFile release];
        [actualStartDate release];
        [actualEndDate release];
    }
    else
        [self addJob:job];
}

- (NSDictionary *)activeJob
{
    return _activeJob;
}

- (void)removeJobAtIndex:(int)i
{
    NSMutableDictionary *job = [[[self jobs] objectAtIndex:i] retain];
    [[self jobs] removeObjectAtIndex:i];
    if ([[job status] isEqual:DBVidiJobStatusActive])
        [self endActiveJob];
    [job release];
    [self scanJobs];
}

- (void)stopActiveJob
{
    if ( _activeJob )
    {
        [self endActiveJob];
        [self scanJobs];
    }
}

- (void)setActiveJobEndDate:(NSCalendarDate *)date;
{
    [_activeJob setObject:date forKey:DBVidiJobSchedEndDateKey];
    [self scanJobs];
}

- (NSMutableArray *)jobs
{
    return _jobs;
}

- (void)rescanJobs:(NSTimer *)ignored
{
    [self scanJobs];
}

- (void)scanJobs
{
    NSMutableDictionary *job;
    NSEnumerator	*jobEnumerator;
    NSDate		*now;
    NSDate		*nextScanDate = [NSCalendarDate distantFuture];
    NSDate		*schedStartDate;
    NSDate		*schedEndDate;
    id			status;

    do
    {
        _needsRescan = NO;
        now = [NSDate date];
        jobEnumerator = [[self jobs] objectEnumerator];
        while ( job = [jobEnumerator nextObject] )
        {
            schedStartDate = [job scheduledStartDate];
            if ( [schedStartDate compare:now]!=NSOrderedDescending )
                            // job scheduled to start in the past
            {
                status = [job status];
                schedEndDate = [job scheduledEndDate];
                if ( schedEndDate && [schedEndDate compare:now]!=NSOrderedDescending  )
                            // job scheduled to end in the past
                {
                    if ( [status isEqual:DBVidiJobStatusActive] )
                    {
                        if (_activeJob)
                            [self endActiveJob];
                        else
                        {
                            [job setObject:DBVidiJobStatusAbended forKey:DBVidiJobStatusKey];
                            if ( _client && job==_selectedJob )
                                [_client serverDidChangeStatusOfSelectedJob];
                        }
                    }
                    else if ( [job recurrence]!=0 )
                    {
                        [self rescheduleJob:job];
                        _needsRescan = YES;
                    }
                }
                else if ( [status isEqual:DBVidiJobStatusActive] )
                {
                            // active job scheduled to end in the future
                    nextScanDate = [schedEndDate earlierDate:nextScanDate];
    //NSLog(@"active, ends in future job");
                }
                else if ( [status isEqual:DBVidiJobStatusScheduled] )
                {
    //NSLog(@"scheduled, get it started");
                            // scheduled job, get it started
                    [self startJob:job];
                    nextScanDate = [schedEndDate earlierDate:nextScanDate];
                }
            }
            else		// job scheduled to start in the future
            {
                nextScanDate = [schedStartDate earlierDate:nextScanDate];
            }
        }
    } while ( _needsRescan );
//NSLog(@"next scan at %@", [nextScanDate description]);    
    [_jobScanTimer release];
    _jobScanTimer = [[NSTimer alloc] initWithFireDate:[nextScanDate addTimeInterval:1] interval:0 target:self selector:@selector(rescanJobs:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_jobScanTimer forMode:NSDefaultRunLoopMode];
//NSLog(@"timer will fire at %@", [[_jobScanTimer fireDate] description]);    
    [[NSUserDefaults standardUserDefaults] setObject:[self jobs] forKey:DBJobsKey];
    if (_client)
        [_client serverDidUpdateJobs];
    [self updateStatusItem];
}

- (void)startJob:(NSMutableDictionary *)job
{
    NSFileManager	*manager = [NSFileManager defaultManager];
    NSString 		*directory;
    NSString		*path;
    BOOL		isDirectory;
    NSString		*extension;
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    directory = [[NSUserDefaults standardUserDefaults] objectForKey:DBMoviesDirectorySettingName];
    
    if (_activeJob)
        [self endActiveJob];
        
    extension = ( [job isAudio] ? @"aiff" : @"dv" );
        
    path = [job scheduledFile];
    
    if (!path || [path length]==0)
    {
        if ( directory!=NULL )
        {
            if ( [manager fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory )
                 path = [directory
                            stringByAppendingPathComponent:[NSString stringWithFormat:@"Vidi %@.%@", [[NSCalendarDate date] descriptionWithCalendarFormat:@"%Y-%m-%d %H-%M-%S"], extension]
                        ];
        }
    }
    
    if ( path && ![job overwrite] && [job recurrence] && [manager fileExistsAtPath:path] )
    {
        int repeat = 0;
        NSString *basePath = [path stringByDeletingPathExtension];
        do
        {
            repeat++;
            path = [NSString stringWithFormat:@"%@ #%d.%@", basePath, repeat, extension];
        } while ( [manager fileExistsAtPath:path] );
    }
    
    if (    path
         && [self hasDevice]
         && ( [[self grabber] isGrabbing] || [[self grabber] startGrabbing] )
        )
    {
        [job setObject:path forKey:DBVidiJobActualFileKey];
        _activeJob = job;
        if ([self startRecordingToFile:path])
        {
            if ( [[self grabber] hasTuner] )
                [self
                    setChannelDictionary:[job objectForKey:DBVidiJobChannelKey]
                    squelch:NO
                    repeat:YES
                ];
        }	// if started recording
        else
            _activeJob = nil;
    }	// if valid path and was/started grabbing
    
    if (_activeJob)
    {
        [job setObject:[NSDate date] forKey:DBVidiJobActualStartDateKey];
        [job setObject:DBVidiJobStatusActive forKey:DBVidiJobStatusKey];
        if (_client)
        {
            if ( job==_selectedJob )
                [_client serverDidChangeStatusOfSelectedJob];
            [_client serverDidStartJob:job];
        }
    }
    else
    {
        [job setObject:DBVidiJobStatusAbended forKey:DBVidiJobStatusKey];
        if (_client)
        {
            if ( job==_selectedJob )
                [_client serverDidChangeStatusOfSelectedJob];
            [_client serverDidAbendJob:job];
        }
        else
        {
            NSString	*scheduledTimeString = [[job scheduledStartDate] descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] objectForKey:NSTimeFormatString] timeZone:nil locale:nil];
            [NSApp activateIgnoringOtherApps:YES];
            // either no device or device busy / bad path
            if ([[self grabber] hasDevice])
            {
                if (![[self grabber] canStartGrabbing])
                {
                    NSString	*message;
                    
                    if ( [[self grabber] firmwareVersion]!=0 )
                        message = NSLocalizedStringFromTable( @"The timer recording from %@ that was scheduled to begin at %@ could not be started because the Studio DV device is currently being used by an application other than Vidi. Close the other application and then open Vidi to reschedule the recording.", @"server", nil );
                    else
                        message =  NSLocalizedStringFromTable( @"The timer recording that was scheduled to begin at %2$@ could not be started because the DV device is currently being used by an application other than Vidi. Close the other application and then open Vidi to reschedule the recording.", @"server", nil );
                    NSRunAlertPanel(
                        NSLocalizedStringFromTable( @"Vidi timer recording could not start", @"server", nil ),
                        message,
                        NSLocalizedStringFromTable( @"OK", @"server", nil ),
                        nil,
                        nil,
                        [[job channel] name],
                        scheduledTimeString
                    );
                }
                else
                {
                    NSString	*message;
                    
                    if ( [[self grabber] firmwareVersion]!=0 )
                        message = NSLocalizedStringFromTable( @"The timer recording from %@ that was scheduled to begin at %@ could not be started due to a problem writing to the file %@.", @"server", nil );
                    else
                        message = NSLocalizedStringFromTable( @"The timer recording that was scheduled to begin at %2$@ could not be started due to a problem writing to the file %3$@.", @"server", nil );
                    NSRunAlertPanel(
                        NSLocalizedStringFromTable( @"Vidi timer recording could not start", @"server", nil ),
                        message,
                        NSLocalizedStringFromTable( @"OK", @"server", nil ),
                        nil,
                        nil,
                        [[job channel] name],
                        scheduledTimeString,
                        path
                    );
                }
            }
            else
            {
                int returnCode = NSRunAlertPanel(
                    NSLocalizedStringFromTable( @"Vidi timer recording could not start", @"server", nil ),
                    NSLocalizedStringFromTable( @"The timer recording that was scheduled to begin at %@ could not be started because Vidi couldn't find a supported DV device. Make sure the device is connected and powered on, then open Vidi to reschedule the recording.", @"server", nil ),
                    NSLocalizedStringFromTable( @"OK", @"server", nil ),
                    NSLocalizedStringFromTable( @"Open Vidi", @"server", nil ),
                    nil,
                    scheduledTimeString
                );
                if ( returnCode==NSAlertAlternateReturn )
                    [self openVidi:nil];
            }
        }
    }
}

- (void)rescheduleJob:(NSMutableDictionary *)job
{
    int recurrence = [job recurrence];
    BOOL overwrite = [job overwrite];
    [job setObject:DBVidiJobStatusScheduled forKey:DBVidiJobStatusKey];
    [job
        setObject:[[job scheduledStartDate] dateByAddingYears:0 months:0 days:recurrence hours:0 minutes:0 seconds:0]
        forKey:DBVidiJobSchedStartDateKey
    ];
    [job
        setObject:[[job scheduledEndDate] dateByAddingYears:0 months:0 days:recurrence hours:0 minutes:0 seconds:0]
        forKey:DBVidiJobSchedEndDateKey
    ];
    if ( overwrite && [[job scheduledFile] length]==0 )
        [job setObject:[job actualFile] forKey:DBVidiJobSchedFileKey];
    if ( _client && job==_selectedJob )
        [_client serverDidChangeStatusOfSelectedJob];
}

- (void)endActiveJob
{
    [self endActiveJobNormally:YES];
}

- (void)endActiveJobNormally:(BOOL)normal
{
    [_activeJob setObject:[NSDate date] forKey:DBVidiJobActualEndDateKey];
    if ( [_activeJob recurrence]==0 )
    {
        [_activeJob
            setObject:( normal ? DBVidiJobStatusCompleted : DBVidiJobStatusAbended )
            forKey:DBVidiJobStatusKey
        ];
        if ( _client && _activeJob==_selectedJob )
            [_client serverDidChangeStatusOfSelectedJob];
    }
    else
    {
        [self rescheduleJob:_activeJob];
        _needsRescan = YES;
    }
    [self stopRecording];
    if (_client)
    {
        if ( normal )
            [_client serverDidFinishJob:_activeJob];
        else
            [_client serverDidAbendJob:_activeJob];
    }
    else
    {
        [[self grabber] stopGrabbing];
    }
    if ( ![_activeJob isPermanent] && normal )
    {
        if ( [_activeJob isEqual:_selectedJob] )
            _selectedJob = nil;
        [[self jobs] removeObject:_activeJob];
    }
    _activeJob = nil;
}

- (void)updateStatusItem
{
    if (_statusItemActive)
    {
        [_statusItem setImage:[self statusImage]];
    }
}

- (DBDVGrabber *)grabber
{
    return _grabber;
}

- (BOOL)isStatusItemActive
{
    return _statusItemActive;
}

- (void)setStatusItemActive:(BOOL)flag
{
    if ( flag==_statusItemActive )
        return;
    _statusItemActive = flag;
    if (flag)
    {
        _statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
        [_statusItem setHighlightMode:YES];
        _statusItemMenu = [NSMenu new];
        
        [_statusItemMenu
            addItemWithTitle:NSLocalizedStringFromTable( @"Status", @"server", @"generic status menu item" )
            action:@selector(statusItemAction:)
            keyEquivalent:@""
        ];
        [_statusItemMenu
            addItemWithTitle:NSLocalizedStringFromTable( @"Show Control Palette", @"server", nil )
            action:@selector(showPalette:)
            keyEquivalent:@""
        ];
        [_statusItemMenu
            addItemWithTitle:NSLocalizedStringFromTable( @"Open Vidi...", @"server", nil )
            action:@selector(openVidi:)
            keyEquivalent:@""
        ];
//        [_statusItemMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
        [_statusItem setMenu:_statusItemMenu];
        [self updateStatusItem];
    }
    else
    {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
//        [_statusItem release];
    }
}

- (void)statusItemAction:(id)sender
{
}

- (void)showPalette:(id)sender
{
    if ( [[self grabber] firmwareVersion]!=0 )
    {
        [_paletteController readUserDefaults];
        [_paletteController setHueControlsVisible:([[self grabber] DVFormat] == DBNTSCFormat)];
        [_paletteController showWindow:nil];
    }
}

- (void)openVidi:(id)sender
{
    [[NSWorkspace sharedWorkspace] launchApplication:@"Vidi.app"];
}

// NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
    SEL action = [menuItem action];
    DBDVGrabber	*grabber = [self grabber];
    
    if ( action==@selector(statusItemAction:) )
    {
        NSString	*deviceItemString;
        if ([grabber hasDevice])
        {
            NSString	*deviceName;
            
            if ( [grabber firmwareVersion]==0 )
                deviceName = NSLocalizedStringFromTable( @"DV device", @"server", @"name for generic DV device (i.e. not a Formac Studio) in various status strings" );
            else if ( [grabber hasTuner] )
                deviceName = NSLocalizedStringFromTable( @"Studio DV/TV", @"server", nil );
            else
                deviceName = NSLocalizedStringFromTable( @"Studio DV", @"server", nil );
            
            if ([grabber isRecording])
                deviceItemString = NSLocalizedStringFromTable( @"Vidi is Recording", @"server", nil );
            else if ([grabber isGrabbing] || ![grabber canStartGrabbing])
                deviceItemString = [NSString
                    stringWithFormat:NSLocalizedStringFromTable(
                        @"%@ in use",
                        @"server",
                        @"parameter is kind of device (DV device, Sutdio DV, Studio DV/TV)."
                    ),
                    deviceName
                ];
            else
                deviceItemString = [NSString
                    stringWithFormat:NSLocalizedStringFromTable(
                        @"%@ connected",
                        @"server",
                        @"parameter is kind of device (DV device, Sutdio DV, Studio DV/TV)."
                    ),
                    deviceName
                ];
        }
        else
            deviceItemString = NSLocalizedStringFromTable( @"No DV device found", @"server", nil );
        [menuItem setTitle:deviceItemString];
        return NO;
    }
    if ( action==@selector(showPalette:) )
    {
        if ( _client || ![grabber hasDevice] || [grabber isRecording] || [grabber firmwareVersion]==0 )
            return NO;
    }
    if ( action==@selector(openVidi:) )
    {
        if (![grabber canStartGrabbing])
            return NO;
    }
    return YES;
}

// NSObject (NSApplicationDelegate)
- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (_activeJob)
        [self endActiveJob];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// NSObject (DBDVGrabberDelegate)

- (NSFileHandle *)grabberNeedsNextFileHandle
{
    NSString		*path;
    NSFileHandle	*result;

    path = [self pathForChunk:_chunkNumber+1];
    
    if ( ![[NSFileManager defaultManager]
                createFileAtPath:path
                contents:nil
                attributes:[NSDictionary
                    dictionaryWithObject:[NSNumber
                        numberWithUnsignedLong:'dvc!'
                    ]
                    forKey:NSFileHFSTypeCode
                ]
            ] )
        return nil;

    result = [NSFileHandle fileHandleForWritingAtPath:path];

    if (result)
    {
        _chunkNumber++;
        fcntl( [result fileDescriptor], F_NOCACHE, YES );       // write to disk, don't waste memory on caching
    }
    return result;
}

- (void)grabberDidStartGrabbing:(DBDVGrabber *)grabber
{
    [self updateStatusItem];
}

- (void)grabberDidStopGrabbing:(DBDVGrabber *)grabber
{
    [self updateStatusItem];
}

- (void)grabberDidStartRecording:(DBDVGrabber *)grabber
{
    [self updateStatusItem];
}

- (void)grabberDidStopRecording:(DBDVGrabber *)grabber
{
    [self updateStatusItem];
}

- (void)grabberHadErrorWriting:(DBDVGrabber *)grabber
{
    [self endActiveJobNormally:NO];
    [self scanJobs];
    if ( !_client )
    {
        [NSApp activateIgnoringOtherApps:YES];
        NSRunAlertPanel(
            NSLocalizedStringFromTable( @"Vidi recording stopped", @"server", nil ),
            NSLocalizedStringFromTable( @"Recording was stopped prematurely due to a problem.", @"server", nil ),
            NSLocalizedStringFromTable( @"OK", @"server", nil ),
            nil,
            nil
        );
    }
}

- (void)grabberDidAcquireDevice:(DBDVGrabber *)grabber
{
    if ( [[self grabber] hasTuner] )
    {
        [_paletteController readUserDefaults];
        [[self grabber]
            setBrightness:[[NSUserDefaults standardUserDefaults] integerForKey:DBBrightnessSettingName]
            contrast:[[NSUserDefaults standardUserDefaults] integerForKey:DBContrastSettingName]
            saturation:[[NSUserDefaults standardUserDefaults] integerForKey:DBSaturationSettingName]
            hue:[[NSUserDefaults standardUserDefaults] integerForKey:DBHueSettingName]
        ];
    }
    [self updateStatusItem];
}

- (void)grabberDidLoseDevice:(DBDVGrabber *)grabber
{
    [[_paletteController window] performClose:nil];
    if ( _activeJob )
        [self endActiveJobNormally:NO];
    [self updateStatusItem];
}

@end
