//
//  DBRadioWindowController.m
//  Vidi
//
//  Created by Mitz Pettel on Feb 22 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBRadioWindowController.h"

#import "DBTVChannel.h"
#import "DBVidi.h"


const float kExtraWindowHeight = 100.0f;

@implementation DBRadioWindowController

- (id)initWithVidi:(DBVidi *)object
{
    self = [super initWithVidi:object];

    if (self)
        _temporaryChannel = [[DBTVChannel alloc] initWithFrequency:90000000 inputSource:DBRadioInput name:@"" volume:1.0 logo:nil];
    return self;
}

- (NSString *)mediumWindowNibName
{
    return @"Radio";
}

- (NSString *)mediumWindowFrameAutosaveName
{
    return @"radio";
}

- (void)windowDidLoad
{
    NSRect frame;

    [super windowDidLoad];

    _isInEditMode = [[NSUserDefaults standardUserDefaults] boolForKey:DBRadioEditingSettingMode];
    [[self window] setShowsResizeIndicator:NO];
    [editModeView retain];
    frame = [editModeView frame];
    if (!_isInEditMode)
        frame.origin.y += kExtraWindowHeight;
    [editModeView setFrameOrigin:frame.origin];
    [editModeView removeFromSuperview];
    [channelPopUp retain];
    [channelsTable setTarget:self];
    [channelsTable setDoubleAction:@selector(editChannelName:)];

    [frequencyStepper setIncrement:0.05];

    if ( _isInEditMode ) {
        [channelPopUp removeFromSuperview];
        [[[self window] contentView] addSubview:editModeView positioned:NSWindowBelow relativeTo:muteButton];
    }
}

- (void)dealloc
{
    [_temporaryChannel release];
    [editModeView release];
    [channelPopUp release];
    [super dealloc];
}

- (void)updateChannelDetails
{
    DBTVChannel *channel = [_vidi selectedChannel];

    [super updateChannelDetails];
    
    [frequencyStepper setFloatValue:[channel frequency] / 1000000.0];
    [frequencyTextField takeFloatValueFrom:frequencyStepper];
}

- (NSMenu *)menuWithChannels
{
    NSMenu *menu = [super menuWithChannels];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:NSLocalizedString(@"Edit Stations", @"menu item") action:@selector(toggleEditMode:) keyEquivalent:@""];
    return menu;
}

- (void)toggleEditMode:(id)sender
{
    NSRect frame = [[self window] frame];
    _isInEditMode = !_isInEditMode;
    if (_isInEditMode) {
        frame.size.height += kExtraWindowHeight;
        frame.origin.y -= kExtraWindowHeight;
        [channelPopUp removeFromSuperview];
        [[self window] setFrame:frame display:YES animate:YES];
        [[[self window] contentView] addSubview:editModeView positioned:NSWindowBelow relativeTo:muteButton];
    } else {
        [editModeView removeFromSuperview];
        frame.size.height -= kExtraWindowHeight;
        frame.origin.y += kExtraWindowHeight;
        [[self window] setFrame:frame display:YES animate:YES];
        [self channelSelectionChanged];
        [[[self window] contentView] addSubview:channelPopUp];
        [[self window] makeFirstResponder:[[self window] initialFirstResponder]];
    }

    [[NSUserDefaults standardUserDefaults] setBool:_isInEditMode forKey:DBRadioEditingSettingMode];
}

- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame
{
    [self toggleEditMode:nil];
    return NO;
}

- (IBAction)takeChannelFrequencyFrom:(id)sender
{
    int frequency = [sender floatValue] * 1000000;
    if (_isInEditMode || ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask))
        [[[self vidi] selectedChannel] setFrequency:frequency];
    else {
        DBTVChannel *channel = [[self vidi] channelForFrequency:frequency];
        if (channel == nil) {
            // no matching channel
            channel = _temporaryChannel;
            [channel setFrequency:frequency];
        }
        [[self vidi] selectChannel:channel];
    }
}

- (DBTVChannel *)newChannel
{
    return [DBTVChannel channelWithFrequency:[[[self vidi] selectedChannel] frequency] inputSource:DBRadioInput name:NSLocalizedString( @"new station", @"name for new radio station" ) volume:1.0 logo:nil];
}

- (IBAction)addClicked:(id)sender
{
    [super addClicked:sender];
    [self editChannelName:nil];
}

- (IBAction)editChannelName:(id)sender
{
    [channelsTable editColumn:0 row:[[self vidi] indexOfSelectedChannel] withEvent:nil select:YES];
}

- (void)recordingStarted
{
    [super recordingStarted];
        
    if ( _isInEditMode )
        [self toggleEditMode:nil];
}

#pragma mark NSObject (NSTableViewDelegate)
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    int row = [channelsTable selectedRow];
    [removeButton setEnabled:row != -1 && [[[self vidi] channels] count] > 1 && ![[self vidi] isRecording]];
    if (row != -1)
        [[self vidi] selectChannelAtIndex:row];
    else {
        [_temporaryChannel setFrequency:[[[self vidi] selectedChannel] frequency]];
        [[self vidi] selectChannel:_temporaryChannel];
    }
}

#pragma mark NSObject (NSWindowDelegate)

- (void)windowWillClose:(NSNotification *)notification
{
    if (_blinkerTimer)
        [_blinkerTimer invalidate];
    [self autorelease];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    return [sender frame].size;
}

@end
