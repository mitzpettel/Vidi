//
//  DBTimerWindowController.h
//  Vidi
//
//  Created by Mitz Pettel on Feb 27 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class DBVidi;

@interface DBTimerWindowController : NSWindowController
{
    DBVidi *_vidi;
    NSArray *_sortedJobs;
    NSTimer *_updateTimer;
    NSString *_timeFormatString;
    NSString *_dateFormatString;
    NSDictionary *_audioFormat;

    IBOutlet NSTableView *tableView;
    IBOutlet NSButton *addButton;
    IBOutlet NSButton *removeButton;
    IBOutlet NSButton *editButton;
    IBOutlet NSPopUpButton *channelPopUp;
    IBOutlet NSPanel *jobSheet;
    IBOutlet NSTextField *startDateField;
    IBOutlet NSTextField *startTimeField;
    IBOutlet NSTextField *endTimeField;
    IBOutlet NSTextField *fileTextField;
    IBOutlet NSButton *selectButton;
    IBOutlet NSTextField *scheduledMinutesTextField;
    IBOutlet NSButton *splitCheckbox;
    IBOutlet NSTextField *audioFormatTextField;
    IBOutlet NSButton *changeAudioFormatButton;

    IBOutlet NSMatrix *recurrenceMatrix;
    IBOutlet NSPopUpButton *dayPopUp;
    IBOutlet NSButton *overwriteCheckbox;
    IBOutlet NSTextField *infoTextField;
    IBOutlet NSImageView *cautionImage;
}

- (IBAction)addClicked:(id)sender;
- (IBAction)editClicked:(id)sender;
- (IBAction)removeClicked:(id)sender;
- (IBAction)jobOKClicked:(id)sender;
- (IBAction)jobCancelClicked:(id)sender;
- (IBAction)selectFile:(id)sender;
- (IBAction)timeFieldChanged:(id)sender;
- (IBAction)recurrenceMatrixChanged:(id)sender;
- (IBAction)changeAudioFormatClicked:(id)sender;
- (IBAction)takeChannelFrom:(id)sender;

- (id)initWithVidi:(DBVidi *)vidi;
- (void)updateAudioFormatText:(BOOL)isAudioOnly;
- (void)updateInfoText;
- (void)updateButtons;
- (void)updateSortedJobs;
- (void)updateChannelPopUp;
- (void)updateScheduledMinutes;

@end
