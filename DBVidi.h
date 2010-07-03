//
//  DBVidi.h
//  Vidi
//
//  Created by Mitz Pettel on Jan 1 2003.
//  Copyright (c) 2003, 2005 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DBDVGrabber.h"
#import "DBVidiServer.h"
#import <SystemConfiguration/SystemConfiguration.h>


@class DBMediumWindowController;
@class DBTimerWindowController;
@class DBTVChannel;

enum DBVidiMedium {
    DBVideoMedium = 0,
    DBRadioMedium = 1
};

typedef enum DBVidiMedium DBVidiMedium;

extern NSString *DBChannelListChangedNotification;
extern NSString *DBChannelSelectionDidChangeNotification;
extern NSString *DBVolumeChangedNotification;
extern NSString *DBPictureSettingsChangedNotification;
extern NSString *DBVidiStartedRecordingNotification;
extern NSString *DBVidiStoppedRecordingNotification;
extern NSString *DBVidiJobsUpdatedNotification;
extern NSString *DBVidiSelectedJobChangedNotification;

extern NSString *DBFloatWindowSettingName;
extern NSString *DBSplitMoviesSettingName;
extern NSString *DBMediumSettingName;
extern NSString *DBRadioEditingSettingMode;
extern NSString *DBAudioFormatSettingName;

extern NSString *DBLastDVFormatKey;
extern unsigned int const DBChunkSize;

@interface DBVidi : NSObject <DBVidiClient> {     
    IBOutlet NSPopUpButton *moviesDirectoryPopUp;
    IBOutlet NSButton *statusItemCheckbox;
    IBOutlet NSButton *floatCheckbox;
    IBOutlet NSButton *changeGammaCheckbox;
    IBOutlet NSButton *splitCheckbox;
    IBOutlet NSTextField *audioFormatTextField;

    IBOutlet NSPanel *extendRecordingSheet;
    IBOutlet NSTextField *extendRecordingTextField;

    NSMutableArray *_videoChannels;
    NSMutableArray *_radioChannels;
    DBTVChannel *_previousChannel;
    DBTVChannel *_currentChannel;
    DBTVChannel *_pushedChannel;
    float _volume;
    BOOL _isMuted;
    BOOL _isConsoleUser;
    NSMutableDictionary *_callKeyChannels;
    BOOL _isRecording;
    NSMenu *_dockMenu;

    NSDistantObject <DBDVGrabber> *_grabber;
    NSDistantObject <DBVidiServer> *_server;
    // Whether the server was there or we launched it
    BOOL _launchedServer;
    DBMediumWindowController *_mediumWindowController;
    DBTimerWindowController *_timerWindowController;

    DBVidiMedium _medium;
    SCDynamicStoreRef _dynamicStore;
}

- (void)acquireServer;
- (IBAction)orderFrontTimerWindow:(id)sender;
- (IBAction)orderFrontVidiAboutPanel:(id)sender;
- (IBAction)takeMediumFrom:(id)sender;
- (IBAction)changedMoviesDirectory:(id)sender;
- (IBAction)takeShowStatusItemFrom:(id)sender;
- (IBAction)takeFloatFrom:(id)sender;
- (IBAction)takeChangeGammaFrom:(id)sender;
- (IBAction)takeSplitFrom:(id)sender;
- (IBAction)changeAudioFormatClicked:(id)sender;
- (void)updateDefaults;

- (IBAction)openVidiWebsite:(id)sender;
- (IBAction)openFeedbackWebsite:(id)sender;

- (IBAction)extendRecordingButtonClicked:(id)sender;

- (void)selectNextChannel;
- (void)selectPreviousChannel;
- (void)flipChannels;
- (void)selectChannelAtIndex:(int)i;

- (int)indexOfChannel:(DBTVChannel *)channel;
- (DBTVChannel *)channelForFrequency:(DBTVFrequency)frequency;
- (int)indexOfSelectedChannel;
- (void)selectChannel:(DBTVChannel *)channel;
- (int)callKeyOfChannel:(DBTVChannel *)chan;
- (BOOL)isRecording;
- (void)startRecordingToFile:(NSString *)path;
- (void)stopRecording;
- (void)setCallKey:(int)key forChannel:(DBTVChannel *)chan;
- (DBTVChannel *)channelWithCallKey:(int)key;
- (void)setVolume:(float)value;
- (NSMutableArray *)channels;

- (float)volume;
- (id <DBDVGrabber>)grabber;
- (NSString *)tunerDisplayName;
- (unsigned)firmwareVersion;
- (id <DBVidiServer>)server;
- (DBTVChannel *)selectedChannel;
- (BOOL)isMuted;
- (void)setMuted:(BOOL)mute;
- (void)setBrightness:(int)b contrast:(int)c saturation:(int)s hue:(int)h;
- (void)addChannel:(DBTVChannel *)chan;
- (void)removeChannelAtIndex:(int)i;
- (void)moveChannelAtIndex:(int)i toIndex:(int)j;

- (NSMutableArray *)formacChannels;

- (void)updateMoviesDirectoryPopUp;
- (void)setMoviesDirectory:(NSString *)path;
- (NSString *)moviesDirectory;

- (void)updateAudioFormatTextField;

- (void)updateDockMenu;
- (NSArray *)_privateChannels;

- (DBVidiMedium)medium;
- (void)setMedium:(DBVidiMedium)med;

@end
