//
//  DBVidi.m
//  Vidi
//
//  Created by Mitz Pettel on Jan 1 2003.
//  Copyright (c) 2003, 2004, 2005 Mitz Pettel. All rights reserved.
//

#import <QuickTime/QuickTime.h>
#import <Carbon/Carbon.h>
#import <unistd.h>

#import "DBVidi.h"
#import "DBDVView.h"
#import "DBTVChannel.h"
#import "DBRadioWindowController.h"
#import "DBVidiWindowController.h"
#import "DBTimerWindowController.h"
#import "DBVidiAboutPanelController.h"
#import "DBAudioCompression.h"
#import "NSDictionary-DBVidiJobAdditions.h"


NSString *DBChannelListChangedNotification = @"DBChannelListChangedNotification";
NSString *DBChannelSelectionDidChangeNotification = @"DBChannelSelectionDidChangeNotification";
NSString *DBVolumeChangedNotification = @"DBVolumeChangedNotification";
NSString *DBPictureSettingsChangedNotification =  @"DBPictureSettingsChangedNotification";
NSString *DBVidiStartedRecordingNotification = @"DBVidiStartedRecordingNotification";
NSString *DBVidiStoppedRecordingNotification = @"DBVidiStoppedRecordingNotification";
NSString *DBVidiJobsUpdatedNotification = @"DBVidiJobsUpdatedNotification";
NSString *DBVidiSelectedJobChangedNotification = @"DBVidiSelectedJobChangedNotification";

NSString *DBFloatWindowSettingName = @"float window";
NSString *DBSplitMoviesSettingName = @"split movies into chunks";
NSString *DBMediumSettingName = @"medium";
NSString *DBRadioEditingSettingMode = @"radio is in edit mode";
NSString *DBAudioFormatSettingName = @"audio format";

NSString *DBLastDVFormatKey = @"last DV format";

unsigned int const DBChunkSize = 2045100000;

@interface DBVidi (DBVidiPrivate)
- (void)setConsoleUser:(BOOL)yn;
@end

void dynamicStoreCallout( SCDynamicStoreRef	store, CFArrayRef changedKeys, void *info )
{
	uid_t					uid;
	CFStringRef			user;
	
	user = SCDynamicStoreCopyConsoleUser( store, &uid, nil );
	CFRelease( user );
	
	[[NSApp delegate] setConsoleUser:( uid==getuid() )];
}

@implementation DBVidi

- (NSMutableArray *)formacChannels
{
    NSMutableArray *channels = [NSMutableArray array];
    NSDictionary *formacDictionary = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.formac.studiotvr"];
    NSEnumerator *formacChannelEnum = [[[formacDictionary objectForKey:@"ChannelList"] objectForKey:@"ChannelList"] objectEnumerator];
    NSDictionary *formacChannel;
    NSString *name;
    DBTVFrequency freq;
    NSImage *logo;
    
    while ( formacChannel = [formacChannelEnum nextObject] )
    {
        if ([[formacChannel objectForKey:@"validBroadcast"] boolValue])
        {
            name = [formacChannel objectForKey:@"customName"];
            if ( name==NULL || [name length]==0 )
                name = [formacChannel objectForKey:@"origName"];
            freq = [[formacChannel objectForKey:@"customFrequency"] floatValue];
            if ( freq==0 )
                freq = [[formacChannel objectForKey:@"origFrequency"] floatValue];
            logo = [NSUnarchiver unarchiveObjectWithData:[formacChannel objectForKey:@"customIcon"]];
            if ( ![logo isValid] )
                logo = NULL;
            [channels
                addObject:[DBTVChannel
                    channelWithFrequency:freq
                    inputSource:DBTunerInput
                    name:name
                    volume:1.0
                    logo:logo
                ]
            ];
        }
    }
    return channels;
}

- (void)setupChannels
{
    NSArray		*channelPlist;
    NSDictionary	*keyToIndex = [[NSUserDefaults standardUserDefaults] objectForKey:DBCallKeysKey];
    NSEnumerator	*enumerator;
    NSDictionary	*currentChannel;
    NSString		*key;
    BOOL		hasTuner = [[self grabber] hasTuner];
    BOOL		isFormac = [self firmwareVersion]>0;

    _callKeyChannels = [[NSMutableDictionary dictionary] retain];
    
    if ( isFormac )
    {
        channelPlist = [[NSUserDefaults standardUserDefaults] objectForKey:DBTVChannelsKey];
        if ( channelPlist==nil || !hasTuner )	// ignore defaults if no tuner
        {
            if ( hasTuner )
            {
                _videoChannels = [[self formacChannels] retain];
                if ( [_videoChannels count]==0 )
                    [_videoChannels addObject:[DBTVChannel
                        channelWithFrequency:48250000
                        inputSource:DBTunerInput
                        name:NSLocalizedString( @"new channel", @"name for auto-generated TV channel" )
                        volume:1.0
                        logo:nil
                    ]];
            }
            else
                _videoChannels = [NSMutableArray new];
                
            [_videoChannels insertObject:[DBTVChannel
                channelWithFrequency:0
                inputSource:DBCompositeInput
                name:NSLocalizedString( @"Composite", @"name for auto-generated channel" )
                volume:1.0
                logo:nil
            ] atIndex:0];
            [_videoChannels insertObject:[DBTVChannel
                channelWithFrequency:0
                inputSource:DBSVideoInput
                name:NSLocalizedString( @"S-Video", @"name for auto-generated channel" )
                volume:1.0
                logo:nil
            ] atIndex:1];
            if ( !hasTuner )
            {
                [_callKeyChannels
                    setObject:[_videoChannels objectAtIndex:0]
                    forKey:@"1"
                ];
                [_callKeyChannels
                    setObject:[_videoChannels objectAtIndex:1]
                    forKey:@"2"
                ];
            }
        }
        else
        {
            _videoChannels = [NSMutableArray new];
            enumerator = [channelPlist objectEnumerator];
            while ( currentChannel = [enumerator nextObject] )
                [_videoChannels addObject:[DBTVChannel channelWithDictionary:currentChannel]];
            if ( keyToIndex!=nil )
            {
                enumerator = [keyToIndex keyEnumerator];
                while ( key = [enumerator nextObject] )
                    [_callKeyChannels
                        setObject:[_videoChannels objectAtIndex:[[keyToIndex objectForKey:key] intValue]]
                        forKey:key
                    ];
            }    
        }

        if ( [[self server] hasRadioTuner] )
        {
            channelPlist = [[NSUserDefaults standardUserDefaults] objectForKey:DBRadioChannelsKey];
            if ( channelPlist==nil )
            {
                _radioChannels = [[NSMutableArray arrayWithObject:[DBTVChannel
                    channelWithFrequency:90000000
                    inputSource:DBRadioInput
                    name:NSLocalizedString( @"new station", @"name for auto-generated radio station" )
                    volume:1.0
                    logo:nil
                ]] retain];
            }
            else
            {
                _radioChannels = [NSMutableArray new];
                enumerator = [channelPlist objectEnumerator];
                while ( currentChannel = [enumerator nextObject] )
                    [_radioChannels addObject:[DBTVChannel channelWithDictionary:currentChannel]];
            }
        }
    }
    else	// non-Formac
        _videoChannels = [[NSMutableArray
            arrayWithObject:[DBTVChannel
                channelWithFrequency:0
                inputSource:DBUnknownInput
                name:@""
                volume:1.0
                logo:nil
            ]
        ] retain];

}

- (id)init
{
    [[NSUserDefaults standardUserDefaults]
        registerDefaults:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:141],			DBBrightnessSettingName,
                [NSNumber numberWithInt:60],			DBContrastSettingName,
                [NSNumber numberWithInt:63],			DBSaturationSettingName,
                [NSNumber numberWithInt:0],			DBHueSettingName,
                [NSHomeDirectory() stringByStandardizingPath],	DBMoviesDirectorySettingName,
                [NSNumber numberWithBool:YES],			DBShowStatusItemSettingName,
                [NSNumber numberWithBool:NO],			DBChangeGammaSettingName,
                [NSNumber numberWithBool:NO],			DBFloatWindowSettingName,
                [NSNumber numberWithBool:NO],			DBRadioEditingSettingMode,
                [NSNumber numberWithBool:NO],			DBSplitMoviesSettingName,
                [NSNumber numberWithInt:DBVideoMedium],		DBMediumSettingName,
                [NSNumber numberWithInt:500],			DBMegabytesToReserveSettingName,
                [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithUnsignedLong:rate32khz],		DBVidiJobAudioSampleRateKey,
                    [NSNumber numberWithInt:16],				DBVidiJobAudioSampleSizeKey,
                    [NSNumber numberWithInt:1],					DBVidiJobAudioChannelsKey,
                    [NSNumber numberWithUnsignedLong:kSoundNotCompressed],	DBVidiJobAudioCompressionKey,
                    nil
                ],						DBAudioFormatSettingName,
//                [NSNumber numberWithBool:YES],			@"DBVidiAllowTunerless",
                [NSNumber numberWithInt:DB4to3AspectRatio],	DBAspectRatioSettingName,
				[NSNumber numberWithBool:YES],			DBHighQualitySettingName,
                nil
            ]
    ];

    _volume = 1.0;
    _isRecording = NO;
	_isConsoleUser = YES;
    [self updateDockMenu];
	
	_dynamicStore = SCDynamicStoreCreate(
		nil,
		(CFStringRef)@"Vidi",
		dynamicStoreCallout,
		nil
	);
	
	SCDynamicStoreSetNotificationKeys(
		_dynamicStore,
		(CFArrayRef)[NSArray
			arrayWithObject:[(NSString *)SCDynamicStoreKeyCreateConsoleUser( nil ) autorelease]
		],
		nil
	);
	
	CFRunLoopAddSource(
		CFRunLoopGetCurrent(),
		SCDynamicStoreCreateRunLoopSource( nil, _dynamicStore , 0 ),
		kCFRunLoopDefaultMode
	);
	
    return self;
}

- (void)awakeFromNib
{
    [self updateMoviesDirectoryPopUp];
    [statusItemCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:DBShowStatusItemSettingName]];
    [floatCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:DBFloatWindowSettingName]];
    [changeGammaCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:DBChangeGammaSettingName]];
    [splitCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:DBSplitMoviesSettingName]];
    [self updateAudioFormatTextField];
}

- (void)dealloc
{
    [_dockMenu release];
    [_pushedChannel release];
    [_callKeyChannels release];
    [_videoChannels release];
    [_radioChannels release];
    [_previousChannel release];
    [_grabber release];
    [super dealloc];
}

- (IBAction)takeMediumFrom:(id)sender
{
    [self setMedium:[sender tag]];
}

- (DBVidiMedium)medium
{
    return _medium;
}

- (void)setMedium:(DBVidiMedium)med
{
    if ( _mediumWindowController==nil || _medium!=med )
    {
        [_mediumWindowController close];	// also releases it
        _medium = med;
        if ( med==DBVideoMedium )
        {
            _mediumWindowController = [DBVidiWindowController alloc];
            if (![self isRecording])
                [self selectChannelAtIndex:[[NSUserDefaults standardUserDefaults] integerForKey:DBTVChannelSettingName]];
        }
        else
        {
            _mediumWindowController = [DBRadioWindowController alloc];
            if (![self isRecording])
                [self selectChannelAtIndex:[[NSUserDefaults standardUserDefaults] integerForKey:DBRadioChannelSettingName]];
        }
        [_previousChannel release];
        _previousChannel = nil;
        [_mediumWindowController initWithVidi:self];
        [_mediumWindowController showWindow:nil];
        [[NSUserDefaults standardUserDefaults] setInteger:med forKey:DBMediumSettingName];
        [self updateDockMenu];
    }
}

- (NSMutableArray *)channels
{
    if (_pushedChannel)
        return [NSArray arrayWithObject:_currentChannel];
    else if ( [self medium]==DBVideoMedium )
        return _videoChannels;
    else
        return _radioChannels;
}

- (NSArray *)_privateChannels
{
    NSMutableArray	*allChannels;
    
    allChannels = [NSMutableArray arrayWithArray:_videoChannels];
    [allChannels addObjectsFromArray:_radioChannels];
    return allChannels;
}

- (DBTVChannel *)selectedChannel
{
    return _currentChannel;
}

- (IBAction)selectChannelFromDockMenuItem:(id)sender
{
    if (![self isRecording])
        [self selectChannelAtIndex:[sender tag]];
}

- (void)selectChannelAtIndex:(int)i
{
    if ( i!=NSNotFound )
    {
        i = MIN( i, [[self channels] count]-1 );
        [self selectChannel:[[self channels] objectAtIndex:i]];
    }
}

- (int)indexOfChannel:(DBTVChannel *)channel
{
    return [[self channels] indexOfObject:channel];
}

- (DBTVChannel *)channelForFrequency:(DBTVFrequency)frequency
{
    NSArray *channels = [self channels];
    int count = [channels count];
    int i;
    DBTVChannel *channel;
    
    for ( i = 0; i<count; i++ )
    {
        channel = [channels objectAtIndex:i];
        if ( abs([channel frequency]-frequency)<=10000 )
            return channel;
    }
    return nil;
}

- (int)indexOfSelectedChannel
{
    return [self indexOfChannel:[self selectedChannel]];
}

- (void)selectChannel:(DBTVChannel *)channel
{
    int i;
    if (_currentChannel!=channel)
    {
        [_previousChannel autorelease];
        _previousChannel = _currentChannel;
        if (_currentChannel)
            [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_currentChannel];
        _currentChannel = [channel retain];
        i = [self indexOfSelectedChannel];
        if ( [self medium]==DBVideoMedium )
            [[NSUserDefaults standardUserDefaults] setInteger:i forKey:DBTVChannelSettingName];
        else if ( [self medium]==DBRadioMedium )
            [[NSUserDefaults standardUserDefaults] setInteger:i forKey:DBRadioChannelSettingName];
        [_server
            setChannelDictionary:[channel dictionary]
            squelch:( [self medium]==DBVideoMedium )
            repeat:( [self medium]==DBVideoMedium )
        ];
        [[self grabber] setVolume:( ( [self isMuted] || !_isConsoleUser ) ? 0 : [channel volume]*[self volume]*256 )];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(channelInfoChanged:) name:DBTVChannelChangedNotification object:_currentChannel];
        [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelSelectionDidChangeNotification object:self];
    }
}

- (void)setBrightness:(int)b contrast:(int)c saturation:(int)s hue:(int)h
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [[self grabber] setBrightness:b contrast:c saturation:s hue:h];
    [defaults setInteger:b forKey:DBBrightnessSettingName];
    [defaults setInteger:c forKey:DBContrastSettingName];
    [defaults setInteger:s forKey:DBSaturationSettingName];
    [defaults setInteger:h forKey:DBHueSettingName];
    [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:DBPictureSettingsChangedNotification object:self] postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnName forModes:nil];
}

- (void)flipChannels
{
    if (_previousChannel)
        [self selectChannel:_previousChannel];
}

- (void)selectNextChannel
{
    int i = [self indexOfSelectedChannel];
    if ( i < [[self channels] count]-1 )
        [self selectChannelAtIndex:(i+1)];
    else
        [self selectChannelAtIndex:0];
}

- (void)selectPreviousChannel
{
    int i = [self indexOfSelectedChannel];
    if ( i==NSNotFound )
        i = 0;
    if ( i > 0 )
        [self selectChannelAtIndex:(i-1)];
    else
        [self selectChannelAtIndex:[[self channels] count]-1];
}

- (IBAction)openVidiWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.mitzpettel.com/software/vidi"]];
}

- (IBAction)openFeedbackWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.mitzpettel.com/feedback/vidi"]];
}

- (IBAction)orderFrontTimerWindow:(id)sender
{
    [_timerWindowController showWindow:nil];
}

- (IBAction)orderFrontVidiAboutPanel:(id)sender
{
    [[DBVidiAboutPanelController sharedAboutPanelController] showPanel:nil];
}

- (IBAction)takeShowStatusItemFrom:(id)sender
{
    BOOL active = [sender state];
    [[NSUserDefaults standardUserDefaults] setBool:active forKey:DBShowStatusItemSettingName];
    if (_server)
        [_server setStatusItemActive:active];
}

- (IBAction)takeChangeGammaFrom:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:[sender state] forKey:DBChangeGammaSettingName];
}

- (IBAction)takeSplitFrom:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:[sender state] forKey:DBSplitMoviesSettingName];
}

- (IBAction)takeFloatFrom:(id)sender
{
    [_mediumWindowController setFloating:[sender state]];
}

- (IBAction)changedMoviesDirectory:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setPrompt:NSLocalizedString( @"Select", @"prompt for movies folder selection panel" )];
    [panel beginSheetForDirectory:[[NSUserDefaults standardUserDefaults] objectForKey:DBMoviesDirectorySettingName] file:nil types:nil modalForWindow:[moviesDirectoryPopUp window] modalDelegate:self didEndSelector:@selector(chooseDirectoryPanel:endedWithReturnCode:contextInfo:) contextInfo:nil];
    [moviesDirectoryPopUp selectItemAtIndex:0];
}

- (void)chooseDirectoryPanel:(NSOpenPanel *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [sheet orderOut:nil];
    if ( returnCode==NSOKButton )
    {
        [self setMoviesDirectory:[sheet filename]];
    }
}

- (void)updateMoviesDirectoryPopUp
{
    NSString *path = [[NSUserDefaults standardUserDefaults] objectForKey:DBMoviesDirectorySettingName];
    NSImage *icon;
    [[moviesDirectoryPopUp itemAtIndex:0] setTitle:[path lastPathComponent]];
    icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    [icon setScalesWhenResized:YES];
    [icon setSize:NSMakeSize(16, 16)];
    [[moviesDirectoryPopUp itemAtIndex:0] setImage:icon];
}

- (IBAction)changeAudioFormatClicked:(id)sender
{
    NSDictionary	*audioFormat;
    
    audioFormat = [DBAudioCompression runStandardSoundCompressionDialogWithFormat:[[NSUserDefaults standardUserDefaults] objectForKey:DBAudioFormatSettingName]];
    if ( audioFormat )
    {
        [[NSUserDefaults standardUserDefaults] setObject:audioFormat forKey:DBAudioFormatSettingName];
        [self updateAudioFormatTextField];
    }
    [[sender window] makeKeyAndOrderFront:nil]; 
}

- (void)updateAudioFormatTextField
{
    [audioFormatTextField setStringValue:[DBAudioCompression descriptionOfFormat:[[NSUserDefaults standardUserDefaults] objectForKey:DBAudioFormatSettingName]]];
}

- (void)setMoviesDirectory:(NSString *)path
{
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:DBMoviesDirectorySettingName];
    [self updateMoviesDirectoryPopUp];
}

- (NSString *)moviesDirectory
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:DBMoviesDirectorySettingName];
}

- (void)updateDefaults
{
    if ( [[self grabber] hasTuner] )
    {
        NSUserDefaults		*defs = [NSUserDefaults standardUserDefaults];
        NSMutableArray		*channelPlist = [NSMutableArray array];
        NSMutableDictionary	*keyToIndex = [NSMutableDictionary dictionary];
        NSEnumerator		*enumerator = [_videoChannels objectEnumerator];
        DBTVChannel		*currentChannel;
        int			i = 0;
        int			k;

        while ( currentChannel = [enumerator nextObject] )
        {
            [channelPlist addObject:[currentChannel dictionary]];
            k = [self callKeyOfChannel:currentChannel];
            if ( k!=0 )
                [keyToIndex setObject:[NSNumber numberWithInt:i] forKey:[NSString stringWithFormat:@"%d", k]];
            i++;
        }
        [defs setObject:channelPlist forKey:DBTVChannelsKey];
        [defs setObject:keyToIndex forKey:DBCallKeysKey];
        channelPlist = [NSMutableArray array];
        enumerator = [_radioChannels objectEnumerator];
        while ( currentChannel = [enumerator nextObject] )
            [channelPlist addObject:[currentChannel dictionary]];
        [defs setObject:channelPlist forKey:DBRadioChannelsKey];
    }
}

- (void)channelVolumeChanged:(NSNotification *)notification
{
    if ([[notification object] isEqual:[self selectedChannel]])
        [self setVolume:[self volume]];
}

- (void)channelInfoChanged:(NSNotification *)notification
{
    DBTVChannel		*channel = [notification object];
    if ([channel isEqual:[self selectedChannel]])
    {
        [_server setChannelDictionary:[channel dictionary] squelch:NO repeat:NO];
    }
    [self updateDefaults];
}

- (void)addChannel:(DBTVChannel *)chan
{
    [[self channels] addObject:chan];
    [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
    [self updateDockMenu];
    [self updateDefaults];
}

- (void)moveChannelAtIndex:(int)i toIndex:(int)j
{
    NSMutableArray *channels = [self channels];
    DBTVChannel *chan = [channels objectAtIndex:i];
    [channels insertObject:chan atIndex:(j /*+ ( i<j ? 1 : 0 )*/ )];
    [channels removeObjectAtIndex:(i + ( i<j ? 0 : 1 ) )];
    [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
    [self updateDockMenu];
    [self updateDefaults];
}

- (void)removeChannelAtIndex:(int)i
{
    NSMutableArray *channels = [self channels];
    DBTVChannel *chan = [channels objectAtIndex:i];
    [channels removeObjectAtIndex:i];
    [self setCallKey:0 forChannel:chan];
    if ( i>[channels count]-1 )
        i--;
    [self selectChannelAtIndex:i];
    [_previousChannel autorelease];
    _previousChannel = NULL;
    [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
    [self updateDockMenu];
    [self updateDefaults];
}

- (id <DBDVGrabber>)grabber
{
    return _grabber;
}

- (NSString *)tunerDisplayName
{
    return [[self grabber] tunerDisplayName];
}

- (unsigned)firmwareVersion
{
    return [[self grabber] firmwareVersion];
}

- (id <DBVidiServer>)server
{
    return _server;
}

// recording

- (BOOL)isRecording
{
    return _isRecording;
}

- (void)startRecordingToFile:(NSString *)path
{
    NSMutableDictionary *job;
    
    job = [NSMutableDictionary vidiJobWithStartDate:[NSCalendarDate date] endDate:[NSCalendarDate distantFuture] channel:_currentChannel file:path comments:@"" permanent:NO];
    if ( [self medium]==DBRadioMedium )
    {
        [job setObject:[NSNumber numberWithBool:YES] forKey:DBVidiJobIsAudioKey];
        [job addEntriesFromDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:DBAudioFormatSettingName]];
    }
    else if ( [[NSUserDefaults standardUserDefaults] boolForKey:DBSplitMoviesSettingName] )
        [job setObject:[NSNumber numberWithUnsignedInt:DBChunkSize] forKey:DBVidiJobChunkSizeKey];
    [_server addJob:job];
}

- (void)stopRecording
{
    [_server stopActiveJob];
}

// sound

- (void)setVolume:(float)value
{
    _volume = value;
    [[self grabber] setVolume:( ( [self isMuted] || !_isConsoleUser ) ? 0 : [[self selectedChannel] volume]*value*256 )];
    [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:DBVolumeChangedNotification object:self] postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnName forModes:nil];
}

- (float)volume
{
    return _volume;
}

- (BOOL)isMuted;
{
    return _isMuted;
}

- (void)setConsoleUser:(BOOL)yn
{
	if ( _isConsoleUser!=yn )
	{
		_isConsoleUser = yn;
		[self setVolume:[self volume]];
	}
}

- (void)setMuted:(BOOL)mute
{
    if ( _isMuted!=mute )
    {
        _isMuted = mute;
        [self setVolume:[self volume]];
    }
}

// Call keys

- (int)callKeyOfChannel:(DBTVChannel *)chan
{
    NSArray *keys = [_callKeyChannels allKeysForObject:chan];
    if ( [keys count]==0 )
        return 0;
    else
        return [[keys objectAtIndex:0] intValue];
}

- (DBTVChannel *)channelWithCallKey:(int)key
{
    if ( [self medium]==DBVideoMedium )
        return [_callKeyChannels objectForKey:[NSString stringWithFormat:@"%d", key]];
    return nil;
}

- (void)setCallKey:(int)key forChannel:(DBTVChannel *)chan
{
    if ( [self medium]==DBVideoMedium )
    {
        [_callKeyChannels removeObjectsForKeys:[_callKeyChannels allKeysForObject:chan]];
        if ( key!=0 )
            [_callKeyChannels setObject:chan forKey:[NSString stringWithFormat:@"%d", key]];
        [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
        [self updateDefaults];
    }
}

- (void)updateDockMenu
{

    if ( _dockMenu )
        [_dockMenu release];
    _dockMenu = [NSMenu new];
    if ( [[self grabber] hasTuner] )
    {
        [[_dockMenu
            addItemWithTitle:NSLocalizedString( @"Video", nil )
            action:@selector(takeMediumFrom:)
            keyEquivalent:@""
        ] setTag:0];
        [[_dockMenu
            addItemWithTitle:NSLocalizedString( @"Radio", nil )
            action:@selector(takeMediumFrom:)
            keyEquivalent:@""
        ] setTag:1];
    }
    if ( [self medium]==DBRadioMedium && ![self isRecording] )
    {
        NSEnumerator	*channelEnumerator;
        DBTVChannel	*channel;
        int 		i = 0;
        
        [_dockMenu addItem:[NSMenuItem separatorItem]];
    
        channelEnumerator = [[self channels] objectEnumerator];
        while ( channel = [channelEnumerator nextObject] )
            [[_dockMenu
                addItemWithTitle:[channel name]
                action:@selector(selectChannelFromDockMenuItem:)
                keyEquivalent:@""
            ] setTag:i++];
    }
}

// NSObject (NSApplicationDelegate)

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
    return _dockMenu;
}

- (void)stopRecordingSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    if ( returnCode==NSAlertAlternateReturn )
        [self stopRecording];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self acquireServer];
}

- (void)pushChannel:(DBTVChannel *)channel
{
    _pushedChannel = _currentChannel;
    _currentChannel = [channel retain];
    [self setVolume:[self volume]];
    // NSLog(@"-[DBVidi pushChannel] sending DBChannelListChangedNotification");
    [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
    [self updateDockMenu];
    // NSLog(@"-[DBVidi pushChannel] sending DBChannelSelectionDidChangeNotification");
    [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelSelectionDidChangeNotification object:self];
    // NSLog(@"-[DBVidi pushChannel] done");
}

- (void)popChannel
{
    if (_pushedChannel)
    {
        DBTVChannel	*wasPushedChannel = _pushedChannel;
        DBVidiMedium	pushedMedium;
        
        _pushedChannel = nil;
        // NSLog(@"-[DBVidi popChannel] sending DBChannelListChangedNotification");
        [[NSNotificationCenter defaultCenter] postNotificationName:DBChannelListChangedNotification object:self];
        [self updateDockMenu];
        // NSLog(@"-[DBVidi popChannel] selecting channel %@", [wasPushedChannel name]);
        // don't pop into a different medium
        pushedMedium = ( [wasPushedChannel inputSource]==DBRadioInput ? DBRadioMedium : DBVideoMedium );
        if ( pushedMedium==[self medium] )
            [self selectChannel:wasPushedChannel];
        else if ( [self medium]==DBVideoMedium )
            [self selectChannel:[[self channels] objectAtIndex:[[NSUserDefaults standardUserDefaults] integerForKey:DBTVChannelSettingName]]];
        else
            [self selectChannel:[[self channels] objectAtIndex:[[NSUserDefaults standardUserDefaults] integerForKey:DBRadioChannelSettingName]]];
        [wasPushedChannel release];
        // NSLog(@"-[DBVidi popChannel] done");
    }
}

- (void)serverDidAbendJob:(NSDictionary *)job
{
    NSString	*scheduledTimeString = [[job scheduledStartDate] descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] objectForKey:NSTimeFormatString] timeZone:nil locale:nil];
    NSString	*channelName = [[job channel] name];
    NSString	*title;
    NSString	*message;
    NSString	*param1;
    NSString	*param2;
    
    if ( _isRecording )
    {
        [self popChannel];
        [[NSNotificationCenter defaultCenter] postNotificationName:DBVidiStoppedRecordingNotification object:self];
        _isRecording = NO;
        title = NSLocalizedString( @"Recording stopped", nil );
        message = NSLocalizedString( @"Recording was stopped prematurely due to a problem.", nil );
        param1 = param2 = nil;
    }
    else
    if ( [[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]] )
    {
        // couldn't start our recording
        title = NSLocalizedString( @"Recording could not start", nil );
        message = NSLocalizedString( @"Recording could not start due to a problem.", nil );
        param1 = param2 = nil;
    }
    else
    {
        // couldn't start timer recording
        title = NSLocalizedString( @"Timer recording could not start", nil );
        if ( [self firmwareVersion]!=0 ) 
            message = NSLocalizedString( @"The timer recording from %@ that was scheduled to begin at %@ could not start due to a problem.", nil );
        else
            message = NSLocalizedString( @"The timer recording that was scheduled to begin at %@ could not start due to a problem.", nil );
        param1 = channelName;
        param2 = scheduledTimeString;
    }
    [_mediumWindowController showWindow:nil];
    NSBeginAlertSheet(
        title,
        NSLocalizedString( @"OK", nil ),
        nil,
        nil,
        [_mediumWindowController window],
        nil,
        nil,
        nil,
        nil,
        message,
        param1,
        param2
    );
}

- (void)serverDidFinishJob:(NSDictionary *)job
{
    [self popChannel];
    [[NSNotificationCenter defaultCenter] postNotificationName:DBVidiStoppedRecordingNotification object:self];
    _isRecording = NO;
    [self updateDockMenu];
}

- (void)startJobSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode dismissTimer:(NSTimer *)timer
{
    [timer invalidate];
    [timer release];
    [sheet orderOut:nil];
    if ( returnCode==NSAlertAlternateReturn )	// stop recording
        [self stopRecording];
}

- (void)dismissStartJobSheet:(NSTimer *)timer
{
    id sheet = [timer userInfo];
    [NSApp endSheet:sheet];
}

- (void)beginRecordingSheetForJob:(NSDictionary *)job starting:(BOOL)flag
{
    id		sheet;
    NSString	*title;
    NSString	*message;
    NSTimer	*dismissTimer;
    
    if ( [[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]] ) // manual
    {
        title = NSLocalizedString( @"Manual recording in progress", nil );
        if ( [self firmwareVersion]!=0 )
            message = NSLocalizedString( @"Vidi is currently recording from %@. During the recording, you cannot change channels.", nil );
        else
            message = NSLocalizedString( @"Vidi is currently recording.", nil );
    }
    else if ( flag )
    {
        title = NSLocalizedString( @"Timer recording started", nil );
        if ( [self firmwareVersion]!=0 )
            message = NSLocalizedString( @"Vidi started recording from %@. Recording will continue until %@. During the recording, you cannot change channels. If you quit Vidi, recording will continue in the background. If you log out, recording will stop.", nil );
        else
            message = NSLocalizedString( @"Vidi started recording. Recording will continue until %2$@. During the recording, you cannot change channels. If you quit Vidi, recording will continue in the background. If you log out, recording will stop.", nil );
    }
    else
    {
        title = NSLocalizedString( @"Timer recording in progress", nil );
        if ( [self firmwareVersion]!=0 )
            message = NSLocalizedString( @"Vidi is currently recording from %@. Recording will continue until %@. During the recording, you cannot change channels. If you quit Vidi, recording will continue in the background. If you log out, recording will stop.", nil );
        else
            message = NSLocalizedString( @"Vidi is currently recording. Recording will continue until %2$@. During the recording, you cannot change channels. If you quit Vidi, recording will continue in the background. If you log out, recording will stop.", nil );
    }
    sheet = NSGetAlertPanel(
        title,
        message,
        NSLocalizedString( @"OK", nil ),
        NSLocalizedString( @"Stop Recording", nil ),
        nil,
        [[job channel] name],
        [[job scheduledEndDate] descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] 
objectForKey:NSTimeFormatString] timeZone:nil locale:nil]
    );
    dismissTimer = [[NSTimer scheduledTimerWithTimeInterval:[[job scheduledEndDate] timeIntervalSinceNow] target:self selector:@selector(dismissStartJobSheet:) userInfo:sheet repeats:NO] retain];
    [_mediumWindowController showWindow:nil];
    [NSApp
        beginSheet:sheet
        modalForWindow:[_mediumWindowController window]
        modalDelegate:self
        didEndSelector:@selector(startJobSheet:endedWithReturnCode:dismissTimer:)
        contextInfo:dismissTimer
    ];
}

- (void)serverDidStartJob:(NSDictionary *)job
{
    _isRecording = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:DBVidiStartedRecordingNotification object:self];
    if (![[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]]) // not our job
    {
        [self pushChannel:[job channel]];
        if ( [[job channel] inputSource]==DBRadioInput )
            [self setMedium:DBRadioMedium];
        else
            [self setMedium:DBVideoMedium];
        [self beginRecordingSheetForJob:job starting:YES];
    }
    else
        [self updateDockMenu];
}

- (void)serverDidUpdateJobs
{
    [[NSNotificationCenter defaultCenter] postNotificationName:DBVidiJobsUpdatedNotification object:self];
}

- (void)serverDidChangeStatusOfSelectedJob
{
    [[NSNotificationCenter defaultCenter] postNotificationName:DBVidiSelectedJobChangedNotification object:self];
}

- (void)serverConnectionDied:(NSNotification *)notification
{
    NSRunCriticalAlertPanel(
        NSLocalizedString( @"An error has occurred", nil ),
        NSLocalizedString( @"The Vidi Server connection died.\n\nVidi will quit.", nil ),
        NSLocalizedString( @"Quit", nil ),
        nil,
        nil
    );
    [NSApp stop:nil];
}

- (void)serverAcquired
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverConnectionDied:) name:NSConnectionDidDieNotification object:[_server connectionForProxy]];
    
    [_server setStatusItemActive:[defaults boolForKey:DBShowStatusItemSettingName]];
    if ( [_server hasDevice] )
    {
        if ([_server setClient:self])
        {
            NSDictionary *activeJob = [_server activeJob];
            _grabber = (NSDistantObject <DBDVGrabber> *)[_server grabber];
            [_grabber setProtocolForProxy:@protocol(DBDVGrabber)];
            [_grabber retain];
            [self setupChannels];
            _isRecording = (activeJob!=nil);
            if (!_isRecording)
            {
                [self setMedium:[[NSUserDefaults standardUserDefaults] integerForKey:DBMediumSettingName]];
            }
            else
            {
                _currentChannel = [[self channels] objectAtIndex:[defaults integerForKey:DBTVChannelSettingName]];
                if ( [[activeJob channel] inputSource]==DBRadioInput )
                    [self setMedium:DBRadioMedium];
                else
                    [self setMedium:DBVideoMedium];
                [self pushChannel:[activeJob channel]];
            }

            _timerWindowController = [[DBTimerWindowController alloc] initWithVidi:self];

            if (_isRecording)
            {
                // announce the recording
                [self beginRecordingSheetForJob:activeJob starting:NO];
            }
        }
        else
        {
            NSString	*title;
            NSString	*message;
            
            if ( [[_server grabber] firmwareVersion]!=0 )
            {
                title = NSLocalizedString( @"Formac Studio in use", nil );
                if ( [[_server grabber] hasTuner] )
                    message = NSLocalizedString(
                        @"The Formac Studio DV/TV is currently being used by another application. To control the Studio DV/TV while it is being used by another application, use the control palette.", 
                        nil
                    );
                else
                    message = NSLocalizedString(
                        @"The Formac Studio DV is currently being used by another application. To control the Studio DV while it is being used by another application, use the control palette.", 
                        nil
                    );

            }
            else
            {
                title = NSLocalizedString( @"DV device in use", nil );
                message = NSLocalizedString(
                    @"The DV device is currently being used by another application.",
                    nil
                );
            }
            
            if ( 
                NSRunAlertPanel(
                    title,
                    message,
                    NSLocalizedString( @"Quit", nil ),
                    ( [[_server grabber] firmwareVersion]!=0 ?
                        NSLocalizedString( @"Show Control Palette", nil ) :
                        nil
                    ),
                    nil
                )
                            == NSAlertAlternateReturn )
            {
                [_server setStatusItemActive:YES];
                [_server showPalette:nil];
            }
            [NSApp terminate:nil];
        }
        
    }
    else
    {
        NSRunAlertPanel(
            NSLocalizedString( @"DV device not found", nil ),
            NSLocalizedString( @"Vidi couldn't find a supported DV device. Make sure the device is connected and powered on, then try again.", nil ),
            NSLocalizedString( @"Quit", nil ),
            nil,
            nil
        );
        [NSApp terminate:nil];
    }
    
}

- (void)acquireServer
{
    NSString	*serverExecutable;
    NSConnection *connection = [NSConnection connectionWithRegisteredName:DBVidiServerName host:nil];
    if ( connection )
    {
        _server = [[connection rootProxy] retain];
        [(NSDistantObject *)_server setProtocolForProxy:@protocol(DBVidiServer)];
        // if the server does not support bundleVersion and die, or it's already the server we've launched, we'll just have to live with it
        if ( !_launchedServer )
        {
            if ( [_server respondsToSelector:@selector(die)] && [_server respondsToSelector:@selector(bundleVersion)] && [_server respondsToSelector:@selector(version044)] )
            {
                if ( [_server bundleVersion]==CFBundleGetVersionNumber(CFBundleGetMainBundle()) && ![[NSUserDefaults standardUserDefaults] boolForKey:@"restartServer"] )
                    [self serverAcquired];
                else
                {
                    [_server die];
                    [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
                    [_server release];
                    _server = nil;
                    connection = nil;
                }
            }
            else
            {
                if ( [NSTask
                    launchedTaskWithLaunchPath:@"/usr/bin/killall"
                    arguments:[NSArray arrayWithObject:@"Vidi Server"]
                ] )
                {
                    [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
                    [_server release];
                    _server = nil;
                    connection = nil;
                }
            }
        }			// if questionable server
        else
            [self serverAcquired];
    }

    if ( !connection )
    {
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(serverStarted:) name:DBVidiServerStartedNotification object:nil];
        serverExecutable = [[NSBundle
            bundleWithPath:[[NSBundle mainBundle]
                pathForResource:@"Vidi Server"
                ofType:@"app"
            ]] executablePath];
        if ( serverExecutable!=nil && [NSTask
            launchedTaskWithLaunchPath:serverExecutable
            arguments:[NSArray array]
        ] )
            _launchedServer = YES;
        else
        {
            NSRunCriticalAlertPanel(
                NSLocalizedString( @"Vidi Server could not start", nil ), 
                NSLocalizedString( @"Vidi encountered a problem starting the Vidi Server process, and therefore it must quit now.", nil ),
                NSLocalizedString( @"Quit", nil ),
                nil,
                nil);
            [NSApp terminate:nil];
        }
    }
}

- (void)serverStarted:(NSNotification *)notification
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:DBVidiServerStartedNotification object:nil];
    [self acquireServer];
}

- (void)extendRecordingSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [NSApp replyToApplicationShouldTerminate:(returnCode==0)];
}

- (IBAction)extendRecordingButtonClicked:(id)sender
{
    [extendRecordingSheet orderOut:nil];
    if ([sender tag]==0)	// extend and quit
    {
// NSLog(@"extend by %d minutes", [extendRecordingTextField intValue]);
        [_server
            setActiveJobEndDate:[NSCalendarDate
                dateWithTimeIntervalSinceNow:60*[extendRecordingTextField intValue]
            ]
        ];
        [NSApp endSheet:extendRecordingSheet returnCode:0];
    }
    else			// cancel
    {
        [NSApp endSheet:extendRecordingSheet returnCode:1];
    }
}

- (void)confirmQuitSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    switch (returnCode)
    {
        case NSAlertDefaultReturn:		// stop recording now
            [self stopRecording];
            [NSApp replyToApplicationShouldTerminate:YES];
            break;
        case NSAlertOtherReturn:		// cancel quit
            [NSApp replyToApplicationShouldTerminate:NO];
            break;
        case NSAlertAlternateReturn:		// continue recording
            [sheet orderOut:nil];
            [extendRecordingTextField setIntValue:5];
            [_mediumWindowController showWindow:nil];
            [NSApp
                beginSheet:extendRecordingSheet
                modalForWindow:[_mediumWindowController window]
                modalDelegate:self
                didEndSelector:@selector(extendRecordingSheet:endedWithReturnCode:contextInfo:)
                contextInfo:nil
            ];
            break;
        default:
            break;
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    NSDictionary 	*job = [_server activeJob];
    if ( job && [[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]])
    {
        [_mediumWindowController showWindow:nil];
        NSBeginAlertSheet(
            NSLocalizedString( @"Do you want to stop recording before quitting?", nil ),
            NSLocalizedString( @"Stop Recording", nil ),
            NSLocalizedString( @"Continue Recording...", nil ),
            NSLocalizedString( @"Cancel", nil ),
            [_mediumWindowController window],
            self,
            @selector(confirmQuitSheet:endedWithReturnCode:contextInfo:),
            nil,
            nil,
            NSLocalizedString( @"Vidi is currently recording. You can stop recording now or continue recording in the background after Vidi quits.", nil )
        );
        return NSTerminateLater;
    }
    else
        return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self updateDefaults];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [_server setClient:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:[_server connectionForProxy]];
}

// NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
    SEL action = [menuItem action];
    if ( action==@selector(takeMediumFrom:) )
    {
        DBVidiMedium medium = [menuItem tag];
        [menuItem setState:( [self medium]==medium )];
        if ( [self isRecording] || ( medium==DBRadioMedium && ![_server hasRadioTuner] ) )
            return NO;
        return YES;
    }

    return YES;
}

@end