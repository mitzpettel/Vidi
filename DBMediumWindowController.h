//
//  DBMediumWindowController.h
//  Vidi
//
//  Created by Mitz Pettel on Mon Mar 17 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class DBTVChannel;
@class DBVidi;

@interface DBMediumWindowController : NSWindowController {
    DBVidi *_vidi;
    
    IBOutlet NSButton *muteButton;
    IBOutlet NSSlider *volumeSlider;

    IBOutlet NSTextField *frequencyTextField;
    IBOutlet NSStepper *frequencyStepper;

    IBOutlet NSButton *removeButton;
    IBOutlet NSButton *addButton;

    IBOutlet NSTableView *channelsTable;
    IBOutlet NSPopUpButton *channelPopUp;

    IBOutlet NSButton *recordButton;
    
    IBOutlet NSButton *nextChannelButton;
    IBOutlet NSButton *previousChannelButton;

    NSTimer *_blinkerTimer;
    BOOL _recordLightStatus;
    NSImage *_recLightOnImage;
    NSImage *_recLightOffImage;
}

- (id)initWithVidi:(DBVidi *)object;
- (DBVidi *)vidi;

- (NSString *)mediumWindowNibName;
- (NSString *)mediumWindowFrameAutosaveName;

- (void)setFloating:(BOOL)flag;
- (NSMenu *)menuWithChannels;
- (void)updateChannelPopUp;

- (IBAction)takeChannelFrom:(id)sender;
- (IBAction)takeChannelFrequencyFrom:(id)sender;
- (IBAction)selectNextChannel:(id)sender;
- (IBAction)selectPreviousChannel:(id)sender;
- (IBAction)takeMutingFrom:(id)sender;
- (IBAction)takeVolumeFrom:(id)sender;
- (IBAction)addClicked:(id)sender;
- (IBAction)removeClicked:(id)sender;
- (IBAction)recordButtonClicked:(id)sender;
- (IBAction)record:(id)sender;
- (IBAction)recordAs:(id)sender;
- (IBAction)stopRecording:(id)sender;

- (void)updateChannelDetails;
- (void)updateVolumeSlider;

- (void)channelSelectionChanged;
- (void)recordingStarted;
- (void)recordingStopped;

- (DBTVChannel *)newChannel;

@end
