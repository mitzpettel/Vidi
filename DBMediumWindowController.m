//
//  DBMediumWindowController.m
//  Vidi
//
//  Created by Mitz Pettel on Mon Mar 17 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBMediumWindowController.h"

#import "DBTVChannel.h"
#import "DBVidi.h"


NSString * const DBChannelRowNumberType = @"DBChannelRowNumber";
NSString * const DBChannelNameColumnIdentifier = @"name";

@implementation DBMediumWindowController

- (id)initWithVidi:(DBVidi *)object
{
    _vidi = object;

    self = [super initWithWindowNibName:[self mediumWindowNibName]];
    [self setShouldCascadeWindows:NO];
    [self setWindowFrameAutosaveName:[self mediumWindowFrameAutosaveName]];
    _recLightOnImage = [[NSImage imageNamed:@"rec light on"] retain];
    _recLightOffImage = [[NSImage imageNamed:@"rec light off"] retain];
    return self;
}

- (DBVidi *)vidi
{
    return _vidi;
}

- (void)channelListChanged:(NSNotification *)notification
{
    [removeButton setEnabled:[[_vidi channels] count] > 1 && ![_vidi isRecording]];
    [channelsTable reloadData];
    [channelsTable selectRow:[_vidi indexOfSelectedChannel] byExtendingSelection:NO];
    [channelsTable setNeedsDisplay:YES];
    [self updateChannelPopUp];
}

- (void)channelSelectionDidChange:(NSNotification *)notification
{
    [self channelSelectionChanged];
}

- (void)channelSelectionChanged
{
    int i = -1;
    NS_DURING
        [self updateChannelDetails];
        i = [_vidi indexOfSelectedChannel];
        if (i != NSNotFound) {
            [channelsTable selectRow:i byExtendingSelection:NO];
            [channelsTable scrollRowToVisible:i];
            [channelPopUp selectItemAtIndex:i];
        } else {
            [channelsTable deselectAll:nil];
            [channelPopUp selectItemAtIndex:-1];
        }
    NS_HANDLER
        NSLog(@"exception in -[DBMediumWindowController channelSelectionChanged]:\n%@", localException);
        NSLog(@"i = %d", i);
        NSLog(@"item array = %@", [channelPopUp itemArray]);
    NS_ENDHANDLER
}

- (void)updateChannelDetails
{
    return;
}

- (void)channelInfoChanged:(NSNotification *)notification
{
    DBTVChannel *channel = [_vidi selectedChannel];
    int i = [_vidi indexOfChannel:channel];
    if ([channel isEqual:[notification object]])
        [self updateChannelDetails];
    if (i != NSNotFound) {
        [channelsTable setNeedsDisplay:YES];
        [[channelPopUp itemAtIndex:[_vidi indexOfChannel:channel]] setTitle:[channel name]];
    }
}

- (void)updateVolumeSlider
{
    BOOL isMuted = [_vidi isMuted];
    [volumeSlider setFloatValue:[_vidi volume]];
    [volumeSlider setEnabled:!isMuted];
    [muteButton setState:(isMuted ? NSOnState : NSOffState)];
}

- (void)volumeUpdated:(NSNotification *)notification
{
    [self updateVolumeSlider];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    [channelsTable registerForDraggedTypes:[NSArray arrayWithObject:DBChannelRowNumberType]];
    [channelsTable setDelegate:self];

    [self updateVolumeSlider];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(volumeUpdated:) name:DBVolumeChangedNotification object:nil];
    [self channelListChanged:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(channelListChanged:) name:DBChannelListChangedNotification object:nil];
    [self channelSelectionChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(channelSelectionDidChange:) name:DBChannelSelectionDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(channelInfoChanged:) name:DBTVChannelChangedNotification object:nil];
    if ([_vidi isRecording])
        [self recordingStarted];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recordingDidStart:) name:DBVidiStartedRecordingNotification object:_vidi];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recordingDidStop:) name:DBVidiStoppedRecordingNotification object:_vidi];

    [self setFloating:[[NSUserDefaults standardUserDefaults] boolForKey:DBFloatWindowSettingName]];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_recLightOnImage release];
    [_recLightOffImage release];
    [super dealloc];
}

- (void)recordButtonBlinker:(NSTimer *)timer
{
    _recordLightStatus = !_recordLightStatus;
    [recordButton setImage:(_recordLightStatus ? _recLightOnImage : _recLightOffImage)];
}

- (void)recordingDidStart:(NSNotification *)notification
{
    [self recordingStarted];
}

- (void)recordingStarted
{
    [[self window] setDocumentEdited:YES];
    [recordButton setImage:_recLightOnImage];
    _recordLightStatus = YES;
    _blinkerTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(recordButtonBlinker:) userInfo:nil repeats:YES] retain];

    [channelPopUp setEnabled:NO];
    [removeButton setEnabled:NO];
    [addButton setEnabled:NO];
    [frequencyTextField setEnabled:NO];
    [frequencyStepper setEnabled:NO];
    [nextChannelButton setEnabled:NO];
    [previousChannelButton setEnabled:NO];
}

- (void)recordingDidStop:(NSNotification *)notification
{
    [self recordingStopped];
}

- (void)recordingStopped
{
    [_blinkerTimer invalidate];
    [_blinkerTimer release];
    _blinkerTimer = nil;
    [recordButton setImage:_recLightOffImage];
    [channelPopUp setEnabled:YES];
    [removeButton setEnabled:[[_vidi channels] count] > 1];
    [addButton setEnabled:YES];
    [frequencyTextField setEnabled:YES];
    [frequencyStepper setEnabled:YES];
    [nextChannelButton setEnabled:YES];
    [previousChannelButton setEnabled:YES];
    [[self window] setDocumentEdited:NO];
}

#pragma mark recording

- (void)stopRecordingSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    if (returnCode == NSAlertDefaultReturn)
        [_vidi stopRecording];
}

- (IBAction)recordButtonClicked:(id)sender
{
    if ([_vidi isRecording]) {
        if ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask)
            [_vidi stopRecording];
        else {
            [self showWindow:nil];
            NSBeginAlertSheet(NSLocalizedString(@"Stop Recording", nil), NSLocalizedString(@"Stop", nil), NSLocalizedString(@"Continue Recording", nil), nil, [self window], self, @selector(stopRecordingSheet:endedWithReturnCode:contextInfo:), nil, nil, NSLocalizedString(@"Are you sure you want to stop the recording?", nil));
        }
    } else {
        if ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask)
            [self recordAs:nil];
        else
            [self record:nil];
    }
}

- (IBAction)record:(id)sender
{
    NSString *directory = [_vidi moviesDirectory];
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory;
    BOOL canRecord = NO;
    if (directory != nil) {
        if ([manager fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory) {
            canRecord = YES;
            [_vidi startRecordingToFile:@""];
        }
    }
    if (!canRecord) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setCanChooseFiles:NO];
        [panel setCanChooseDirectories:YES];
        [panel setPrompt:NSLocalizedString(@"Select", @"prompt for movie destination selection panel")];
        [self showWindow:nil];
        [panel beginSheetForDirectory:directory file:nil types:nil modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(chooseDirectoryPanel:endedWithReturnCode:contextInfo:) contextInfo:nil];
    }
}

- (void)chooseDirectoryPanel:(NSOpenPanel *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [sheet orderOut:nil];
    if (returnCode == NSOKButton) {
        [_vidi setMoviesDirectory:[sheet filename]];
        if (contextInfo==nil)
            [self record:nil];
    }
}

- (IBAction)recordAs:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setPrompt:NSLocalizedString(@"Record", @"prompt for record panel")];
    [panel setRequiredFileType:([[self vidi] medium] == DBVideoMedium ? @"dv" : @"aiff")];
    [self showWindow:nil];
    [panel beginSheetForDirectory:nil file:nil modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [sheet orderOut:nil];
    if (returnCode == NSOKButton)
        [_vidi startRecordingToFile:[sheet filename]];
}

- (IBAction)stopRecording:(id)sender
{
    [_vidi stopRecording];
}

//

- (IBAction)takeChannelFrom:(id)sender
{
    [_vidi selectChannelAtIndex:[sender indexOfSelectedItem]];
    [[self window] makeFirstResponder:[[self window] initialFirstResponder]];
}

- (IBAction)takeChannelFrequencyFrom:(id)sender
{
    [[_vidi selectedChannel] setFrequency:[sender floatValue] * 1000000];
}

- (IBAction)selectNextChannel:(id)sender
{
    [_vidi selectNextChannel];
    [[self window] makeFirstResponder:[[self window] initialFirstResponder]];
}

- (IBAction)selectPreviousChannel:(id)sender
{
    [_vidi selectPreviousChannel];
    [[self window] makeFirstResponder:[[self window] initialFirstResponder]];
}

- (IBAction)takeMutingFrom:(id)sender
{
    [_vidi setMuted:[sender intValue]];
}

- (IBAction)takeVolumeFrom:(id)sender
{
    [_vidi setVolume:[sender floatValue]];
}

- (IBAction)removeClicked:(id)sender
{
    [_vidi removeChannelAtIndex:[channelsTable selectedRow]];
}

- (NSString *)mediumWindowNibName
{
    [NSException raise:NSInvalidArgumentException format:@"-[DBMediumWindowController mediumWindowNibName] called"];
    return nil;
}

- (NSString *)mediumWindowFrameAutosaveName
{
    [NSException raise:NSInvalidArgumentException format:@"-[DBMediumWindowController mediumWindowFrameAutosaveName] called"];
    return nil;
}

- (void)setFloating:(BOOL)flag
{
    [[self window] setLevel:flag ? NSFloatingWindowLevel : NSNormalWindowLevel];
    [[NSUserDefaults standardUserDefaults] setBool:flag forKey:DBFloatWindowSettingName];
}

- (NSMenu *)menuWithChannels
{
    NSArray *channels = [_vidi channels];
    int count = [channels count];
    int i;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (i = 0; i<count; i++)
        [menu addItemWithTitle:[[channels objectAtIndex:i] name] action:nil keyEquivalent:@""];
    return [menu autorelease];
}

- (void)updateChannelPopUp
{
    NS_DURING
        [channelPopUp selectItemAtIndex:-1];
        [channelPopUp setMenu:[self menuWithChannels]];
        [channelPopUp selectItemAtIndex:[_vidi indexOfSelectedChannel]];
    NS_HANDLER
        NSLog(@"exception in -[DBMediumWindowController updateChannelPopUp]:\n%@", localException);
        NSLog(@"[_vidi indexOfSelectedChannel] = %i", [_vidi indexOfSelectedChannel]);
        NSLog(@"item array = %@", [channelPopUp itemArray]);
    NS_ENDHANDLER
}

#pragma mark NSObject (NSControlSubclassDelegate)
//    						(frequency field)
- (BOOL)control:(NSControl *)control isValidObject:(id)object
{
    if (object == nil) {
        NSBeep();
        return NO;
    }
    return YES;
}

- (DBTVChannel *)newChannel
{
    [NSException raise:NSInvalidArgumentException format:@"-[DBMediumWindowController newChannel] called"];
    return nil;
}

- (IBAction)addClicked:(id)sender
{
    int lastRow;

    [_vidi addChannel:[self newChannel]];
    lastRow = [[_vidi channels] count] - 1;
    [_vidi selectChannelAtIndex:lastRow];
}

#pragma mark NSWindow delegate

- (BOOL)windowShouldClose:(id)sender
{
    [NSApp terminate:nil];
    return NO;
}

#pragma mark NSTableView delegate

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tv
{
    return ![_vidi isRecording];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    int row = [channelsTable selectedRow];
    [removeButton setEnabled:(row != -1 && [[_vidi channels] count] > 1 && ![_vidi isRecording])];
    if (row != -1)
        [_vidi selectChannelAtIndex:row];
}

#pragma mark NSTableDataSource

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [[_vidi channels] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
    NSString *identifier = [tableColumn identifier];
    DBTVChannel *channel = [[_vidi channels] objectAtIndex:row];
    if ([identifier isEqual:DBChannelNameColumnIdentifier])
        return [channel name];
    return @"";
}

- (BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
    int row = [[rows objectAtIndex:0] intValue];
    [pboard declareTypes:[NSArray arrayWithObject:DBChannelRowNumberType] owner:nil];
    [pboard setString:[NSString stringWithFormat:@"%d", row] forType:DBChannelRowNumberType];
    return YES;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
    NSString *identifier = [tableColumn identifier];
    DBTVChannel *channel = [[_vidi channels] objectAtIndex:row];
    if ([identifier isEqual:DBChannelNameColumnIdentifier])
        [channel setName:object];
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op
{
    [tv setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op
{
    int srcRow = [[[info draggingPasteboard] stringForType:DBChannelRowNumberType] intValue];
    [_vidi moveChannelAtIndex:srcRow toIndex:row];
    return YES;
}

@end
