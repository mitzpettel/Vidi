//
//  DBVidiWindowController.m
//  Vidi
//
//  Created by Mitz Pettel on Sat Feb 01 2003.
//  Copyright (c) 2003, 2004 Mitz Pettel. All rights reserved.
//

#import "DBVidiWindowController.h"

#import "DBDVView.h"
#import "DBTVChannel.h"
#import "DBTVRemoteControl.h"
#import "DBVidi.h"
#import "DBVidiWindow.h"
#import "ScreenSaverPrivate.h"

extern double CGSSecondsSinceLastInputEvent();

static AspectRatioInfo _aspectRatios[] = {
    {
        DB4to3AspectRatio,
        1, 1,
        1, 1,
        48, 36
    },
    {
        DB16to9AspectRatio,
        1, 1,
        1, 1,
        64, 36
    },
    {
        DBPALSquareAspectRatio,
        702, 720,
        1, 1,
        48, 36
    },
    {
        DB16to9CropAspectRatio,
        1, 1,
        3, 4,
        48, 27
    }
};

@implementation DBVidiWindowController

- (id)initWithVidi:(DBVidi *)object
{
    self = [super initWithVidi:object];
    if (self) {
        _hasTuner = [[[self vidi] grabber] hasTuner];
        _isFormac = ( [[self vidi] firmwareVersion]!=0 );
    }
    return self;
}

- (NSString *)mediumWindowNibName
{
    return @"VidiWindow";
}

- (NSString *)mediumWindowFrameAutosaveName
{
    return @"monitor";
}

- (void)dealloc
{
    if (!_isFormac) {
        // Formac-related controls hidden
        [channelPopUp release];
        [nextChannelButton release];
        [previousChannelButton release];
        [channelNameDisplay release];
        [channelLogoDisplay release];
    }
    [_popUpWindow close];
    [super dealloc];
}

- (void)updateNormalViewSizeAndCropping
{
    AspectRatioInfo *aspectRatio = _aspectRatios + [[NSUserDefaults standardUserDefaults] integerForKey:DBAspectRatioSettingName];
    NSSize DVFrameSize;
    int vCrop;
    int hCrop;
    int t = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskTopSettingName];
    int b = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskBottomSettingName];
    int l = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskLeftSettingName];
    int r = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskRightSettingName];

    DVFrameSize = [view DVFrameSize];
    vCrop = DVFrameSize.height * (aspectRatio->clipHeightDenom-aspectRatio->clipHeightNum) / aspectRatio->clipHeightDenom / 2;
    hCrop = DVFrameSize.width * (aspectRatio->clipWidthDenom-aspectRatio->clipWidthNum) / aspectRatio->clipWidthDenom / 2;
    // what's left to mask after we crop?
    t = MAX(0, t - vCrop);
    b = MAX(0, b - vCrop);
    l = MAX(0, l - hCrop);
    r = MAX(0, r - hCrop);

    _normalViewSize.height = DVFrameSize.height*aspectRatio->clipHeightNum/aspectRatio->clipHeightDenom;
    _normalViewSize.width = aspectRatio->ratioWidth*_normalViewSize.height/aspectRatio->ratioHeight;
    [view setCroppingTop:vCrop+t left:hCrop+l bottom:vCrop+b right:hCrop+r];
    [view setBorderTop:t * aspectRatio->clipHeightDenom / aspectRatio->clipHeightNum left:l * aspectRatio->clipWidthDenom / aspectRatio->clipWidthNum bottom:b * aspectRatio->clipHeightDenom / aspectRatio->clipHeightNum right:r * aspectRatio->clipWidthDenom / aspectRatio->clipWidthNum];
}

- (void)updateBigViewSizeAndCropping
{
    AspectRatioInfo *aspectRatio = _aspectRatios + _fullScreenAspectRatio;
    NSSize DVFrameSize = [_bigDBDVView DVFrameSize];
    int vBorder;
    int hBorder;
    NSSize screenSize = [_bigDBDVView frame].size;
    NSSize croppedSize;
    NSSize activeSize;
    int t = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskTopSettingName];
    int b = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskBottomSettingName];
    int l = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskLeftSettingName];
    int r = [[NSUserDefaults standardUserDefaults] integerForKey:DBMaskRightSettingName];
    int activeRatioWidth;
    int activeRatioHeight;

    croppedSize.width = DVFrameSize.width * aspectRatio->clipWidthNum/aspectRatio->clipWidthDenom;
    croppedSize.height = DVFrameSize.height * aspectRatio->clipHeightNum/aspectRatio->clipHeightDenom;

    t = MAX(t, (DVFrameSize.height - croppedSize.height) / 2);
    l = MAX(l, (DVFrameSize.width - croppedSize.width) / 2);
    b = MAX(b, (DVFrameSize.height - croppedSize.height) / 2);
    r = MAX(r, (DVFrameSize.width - croppedSize.width) / 2);

    [_bigDBDVView setCroppingTop:t left:l bottom:b right:r];

    activeSize.width = DVFrameSize.width - l - r;
    activeSize.height = DVFrameSize.height - t - b;

    activeRatioWidth = aspectRatio->ratioWidth * activeSize.width * croppedSize.height;
    activeRatioHeight = aspectRatio->ratioHeight * activeSize.height * croppedSize.width;

    if (DVFrameSize.width * (screenSize.width - activeRatioWidth * screenSize.height / activeRatioHeight) / screenSize.width > 0) {
        hBorder = DVFrameSize.width * (screenSize.width - screenSize.height * activeRatioWidth / activeRatioHeight) / screenSize.width;
        vBorder = 0;
    } else {
        vBorder = DVFrameSize.height * (screenSize.height - screenSize.width * activeRatioHeight / activeRatioWidth) / screenSize.height;
        hBorder = 0;
    }

    [_bigDBDVView setBorderTop:vBorder / 2 left:hBorder / 2 bottom:vBorder / 2 right:hBorder / 2];
}

- (void)windowDidLoad
{
    id lastDVFormat;

    [super windowDidLoad];

    _activeView = view;
    _borderHeight = [[self window] frame].size.height - [view frame].size.height;
    _borderWidth = [[self window] frame].size.width - [view frame].size.width;

    // set up the full screen pop up
    _popUpWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, -72, 600, 72) styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_popUpWindow setHasShadow:NO];
    [_popUpWindow setOpaque:NO];
    [_popUpWindow setBackgroundColor:[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:0.5]];
    [_popUpWindow setContentView:popUp];

    [self updatePictureSliders];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pictureSettingsUpdated:) name:DBPictureSettingsChangedNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:NSApplicationWillResignActiveNotification object:NSApp];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:NSApplicationWillTerminateNotification object:NSApp];

    _cursorTimer = [[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(cursorHider:) userInfo:nil repeats:YES] retain];

    [view setGrabber:[_vidi grabber]];
    [view setHighQuality:[[NSUserDefaults standardUserDefaults] boolForKey:DBHighQualitySettingName]];
    [view setSingleField:[[NSUserDefaults standardUserDefaults] boolForKey:DBSingleFieldSettingName]];
    [view setDeinterlace:[[NSUserDefaults standardUserDefaults] boolForKey:DBDeinterlaceSettingName]];
    [self updateNormalViewSizeAndCropping];

    lastDVFormat = [[NSUserDefaults standardUserDefaults] objectForKey:DBLastDVFormatKey];
    if (lastDVFormat == nil || [lastDVFormat intValue] != [[_vidi grabber] DVFormat]) {
        NSRect windowFrame = [[self window] frame];
        windowFrame.size = _normalViewSize;
        windowFrame.size.width += _borderWidth;
        windowFrame.size.height += _borderHeight;
        [[self window] setFrame:windowFrame display:NO];
        [[self window] center];
        [[NSUserDefaults standardUserDefaults] setInteger:[[_vidi grabber] DVFormat] forKey:DBLastDVFormatKey];
    }

    if ([[_vidi grabber] DVFormat] != DBNTSCFormat)
        [[hueControls retain] removeFromSuperview];

    [frequencyStepper setIncrement:1 / 16.0];
    if (!_isFormac) {
        // Hide Formac-related controls
        NSRect recordButtonSuperFrame = [[recordButton superview] frame];
        [settingsButton removeFromSuperview];
        [[channelPopUp retain] removeFromSuperview];
        [[recordButton superview] setFrameOrigin:NSMakePoint(recordButtonSuperFrame.origin.x + 29, recordButtonSuperFrame.origin.y)];
        [[nextChannelButton retain] removeFromSuperview];
        [[previousChannelButton retain] removeFromSuperview];
        [[channelNameDisplay retain] removeFromSuperview];
        [[channelLogoDisplay retain] removeFromSuperview];
        [[self window] display];
    } else if (!_hasTuner) {
         // Hide tuner-related controls
        NSView *videoSettingsView = [brightnessSlider superview];
        NSRect contentFrame = [[settingsDrawer contentView] frame];
        NSView *newContentView = [[[NSView alloc] initWithFrame:contentFrame] autorelease];

        [[videoSettingsView retain] autorelease];
        [settingsDrawer setContentView:newContentView];
        [newContentView addSubview:videoSettingsView];
        [videoSettingsView setFrameOrigin:NSMakePoint(0, contentFrame.size.height -  [videoSettingsView frame].size.height)];
    }

    [maskTopStepper setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskTopSettingName]];
    [maskLeftStepper setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskLeftSettingName]];
    [maskBottomStepper setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskBottomSettingName]];
    [maskRightStepper setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskRightSettingName]];
    [maskTopTextField setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskTopSettingName]];
    [maskLeftTextField setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskLeftSettingName]];
    [maskBottomTextField setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskBottomSettingName]];
    [maskRightTextField setIntValue:[[NSUserDefaults standardUserDefaults] integerForKey:DBMaskRightSettingName]];
}

- (void)recordingStarted
{
    [super recordingStarted];

    [channelNameTextField setEnabled:NO];
    [inputPopUp setEnabled:NO];
    [logoEditableImageView setEnabled:NO];
}

- (void)recordingStopped
{
    [super recordingStopped];

    [channelNameTextField setEnabled:YES];
    [inputPopUp setEnabled:YES];
    [logoEditableImageView setEnabled:YES];
}

- (void)updateChannelDetails
{
    DBTVChannel *channel = [_vidi selectedChannel];
    DBDVInputSource inputSource = [channel inputSource]; 

    [super updateChannelDetails];

    [logoEditableImageView setImage:[channel logo]];
    if (inputSource == DBTunerInput) {
        [frequencyTextField setFloatValue:[channel frequency] / 1000000.0];
        [frequencyStepper setFloatValue:[channel frequency] / 1000000.0];
    } else
        [frequencyTextField setStringValue:@""];
    [frequencyTextField setEnabled:inputSource == DBTunerInput && ![_vidi isRecording]];
    [frequencyStepper setEnabled:inputSource == DBTunerInput && ![_vidi isRecording]];
    [channelNameTextField setStringValue:[channel name]];
    [channelVolumeSlider setFloatValue:[channel volume]];
    [callKeyPopUp selectItemAtIndex:[_vidi callKeyOfChannel:channel]];
    [inputPopUp selectItemAtIndex:[inputPopUp indexOfItemWithTag:inputSource]];
    [channelLogoDisplay setImage:[channel logo]];
    [channelNameDisplay setStringValue:[channel name]];
}

- (void)updateVolumeSlider
{
    BOOL isMuted = [[self vidi] isMuted];

    [super updateVolumeSlider];

    [fullScrVolumeSlider setFloatValue:[_vidi volume]];
    [fullScrVolumeSlider setEnabled:!isMuted];
}

- (void)updatePictureSliders
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [brightnessSlider setIntValue:[defaults integerForKey:DBBrightnessSettingName]];
    [contrastSlider setIntValue:[defaults integerForKey:DBContrastSettingName]];
    [saturationSlider setIntValue:[defaults integerForKey:DBSaturationSettingName]];
    [hueSlider setIntValue:[defaults integerForKey:DBHueSettingName]];
}

- (void)pictureSettingsUpdated:(NSNotification *)notification
{
    [self updatePictureSliders];
}

- (DBTVChannel *)newChannel
{
    return [DBTVChannel channelWithFrequency:48250000 inputSource:DBTunerInput name:NSLocalizedString(@"new channel", @"name for new TV channel") volume:1.0 logo:nil];
}

- (IBAction)addClicked:(id)sender
{
    [super addClicked:sender];
    [[self window] makeFirstResponder:channelNameTextField];
}

- (IBAction)toggleHighQuality:(id)sender
{
    BOOL highQuality = [[NSUserDefaults standardUserDefaults] boolForKey:DBHighQualitySettingName];

    [[NSUserDefaults standardUserDefaults] setBool:!highQuality forKey:DBHighQualitySettingName];
    [_activeView setHighQuality:!highQuality];
}

- (IBAction)toggleSingleField:(id)sender
{
    BOOL singleField = [[NSUserDefaults standardUserDefaults] boolForKey:DBSingleFieldSettingName];

    [[NSUserDefaults standardUserDefaults] setBool:!singleField forKey:DBSingleFieldSettingName];
    [_activeView setSingleField:!singleField];
}

- (IBAction)toggleDeinterlace:(id)sender
{
    BOOL deinterlace = [[NSUserDefaults standardUserDefaults] boolForKey:DBDeinterlaceSettingName];

    [[NSUserDefaults standardUserDefaults] setBool:!deinterlace forKey:DBDeinterlaceSettingName];
    [_activeView setDeinterlace:!deinterlace];
}

- (IBAction)takeChannelInputFrom:(id)sender
{
    [[_vidi selectedChannel] setInputSource:[[sender selectedItem] tag]];
}

- (IBAction)takeChannelNameFrom:(id)sender
{
    [[_vidi selectedChannel] setName:[sender stringValue]];
}

- (IBAction)takeChannelVolumeFrom:(id)sender
{
    [[_vidi selectedChannel] setVolume:[sender floatValue]];
    [_vidi setVolume:[_vidi volume]];
}

- (IBAction)takeChannelLogoFrom:(id)sender
{
    [[_vidi selectedChannel] setLogo:[sender image]];
}

- (IBAction)takeChannelCallKeyFrom:(id)sender
{
    [_vidi setCallKey:[sender indexOfSelectedItem] forChannel:[_vidi selectedChannel]];
}

- (IBAction)pictureSettingsChanged:(id)sender
{
    int brightness = [brightnessSlider intValue];
    int contrast = [contrastSlider intValue];
    int saturation = [saturationSlider intValue];
    int hue = [hueSlider intValue];
    [_vidi setBrightness:brightness contrast:contrast saturation:saturation hue:hue];
}

- (IBAction)toggleSettingsDrawer:(id)sender
{
    [settingsDrawer toggle:sender];
}

- (IBAction)zoomWindow:(id)sender
{
    int halves;
    NSRect newFrame = [[self window] frame];
    NSSize newSize;

    switch ([sender tag]) {
        case 0:
            halves = 1;
            break;
        case 1:
            halves = 2;
            break;
        case 2:
            halves = 4;
            break;
        default:
            halves = 2;
            break;
    }

    newSize.width = _normalViewSize.width * halves / 2;
    newSize.height = _normalViewSize.height * halves / 2;
    newSize.width += _borderWidth;
    newSize.height += _borderHeight;
//  newFrame.origin.x -= newSize.width-newFrame.size.width;
    newFrame.origin.y -= newSize.height-newFrame.size.height;
    newFrame.size = newSize;
    [[self window] setFrame:newFrame display:YES];
}

#pragma mark Full screen

- (void)beginFullScreen
{
    NSRect screenFrame = NSZeroRect;
    NSRect hotzone;
    DBTVRemoteControl *fullScreenRemote;

    if (_isFullScreen)
        return;

    [view setGrabber:nil];
    if (!_fullScreenWindow) {
        _fullScreenWindow = [[DBVidiWindow alloc] initWithContentRect:[[[self window] screen] frame] styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
        [_fullScreenWindow setWindowController:self];
        [_fullScreenWindow setDelegate:self];
        [_fullScreenWindow setTitle:[[self window] title]];
        [_fullScreenWindow setBackgroundColor:[NSColor blackColor]];
        screenFrame = [_fullScreenWindow frame];
        _bigDBDVView = [[DBDVView alloc] initWithFrame:screenFrame];
        [_bigDBDVView setFullScreen:YES];
        [[_fullScreenWindow contentView] addSubview:_bigDBDVView];
        _fullScreenAspectRatio = [[NSUserDefaults standardUserDefaults] integerForKey:DBAspectRatioSettingName];
        fullScreenRemote = [[DBTVRemoteControl alloc] initWithFrame:NSMakeRect(-10, -10, 10, 10)];
        [[_fullScreenWindow contentView] addSubview:[fullScreenRemote autorelease]];
        [fullScreenRemote setController:self];

        SetSystemUIMode(kUIModeAllHidden, 0);
        hotzone = [[_fullScreenWindow contentView] frame];
        hotzone.size.height = 2;
        _hotzoneTag = [[_fullScreenWindow contentView] addTrackingRect:hotzone owner:self userData:nil assumeInside:NO];
        hotzone = [[_fullScreenWindow contentView] frame];
        hotzone.size.height -= 72;
        hotzone.origin.y += 72;
        _popUpShowingFrame.size = NSMakeSize(600, 72);
        _popUpShowingFrame.origin.x = (hotzone.size.width - 600) / 2;
        _popUpShowingFrame.origin.y = 0;
        _popUpHiddenFrame = _popUpShowingFrame;
        _popUpHiddenFrame.origin.y = -72;
        _popUpTag = [[_fullScreenWindow contentView] addTrackingRect:hotzone owner:self userData:nil assumeInside:NO];
    } else {
        screenFrame = [_fullScreenWindow frame];
        [_bigDBDVView setFrame:screenFrame];
    }

    [_popUpWindow setFrame:_popUpHiddenFrame display:NO];
    _popUpActive = NO;
    [_popUpWindow setLevel:NSModalPanelWindowLevel];

    // FIXME: Should CGDisplayCapture and CGDisplayHideCursor be used here?

    [NSCursor setHiddenUntilMouseMoves:YES];

    CGGetDisplayTransferByTable(kCGDirectMainDisplay, 256, _savedTransferTables.redTable, _savedTransferTables.greenTable, _savedTransferTables.blueTable, &_savedTransferTables.sampleCount);

    if ([[NSUserDefaults standardUserDefaults] boolForKey:DBChangeGammaSettingName])
        CGSetDisplayTransferByFormula(kCGDirectMainDisplay, 0, 1, 1 / 1.8, 0, 1, 1 / 1.8, 0, 1, 1 / 1.8);

    [_bigDBDVView setHighQuality:[view highQuality]];
    [_bigDBDVView setSingleField:[view singleField]];
    [_bigDBDVView setDeinterlace:[view deinterlace]];
    [_bigDBDVView setGrabber:[_vidi grabber]];
    [self updateBigViewSizeAndCropping];
    _activeView = _bigDBDVView;
    [_popUpWindow orderFront:nil];
    [[self window] orderOut:nil];
    [maskingPanel orderOut:nil];
    [_fullScreenWindow makeKeyAndOrderFront:nil];
    [[ScreenSaverController controller] setScreenSaverCanRun:NO];
    _isFullScreen = YES;
}

- (void)endFullScreen
{
    if (!_isFullScreen)
        return;

    NSWindow *keyWindow = [NSApp keyWindow];
    BOOL wasKey = [keyWindow isEqual:_fullScreenWindow];

    [[ScreenSaverController controller] setScreenSaverCanRun:YES];
    [_bigDBDVView setGrabber:NULL];
    _activeView = view;
    [view setHighQuality:[_bigDBDVView highQuality]];
    [view setSingleField:[_bigDBDVView singleField]];
    [view setDeinterlace:[_bigDBDVView deinterlace]];
    [_bigDBDVView release];
    _bigDBDVView = nil;
    [_fullScreenWindow setDelegate:nil];
    if (NSDisableScreenUpdates)   // available only on 10.3 and later
        NSDisableScreenUpdates();
    [_fullScreenWindow orderOut:nil];
    SetSystemUIMode(kUIModeNormal, 0);
    [_fullScreenWindow release];
    _fullScreenWindow = nil;
    [_popUpWindow orderOut:nil];
    _popUpActive = NO;
    if (wasKey)
        [[self window] makeKeyAndOrderFront:nil];
    else {
        [[self window] orderFront:nil];
        [keyWindow makeKeyAndOrderFront:nil];
    }
    [view setGrabber:[_vidi grabber]];
    _isFullScreen = NO;
    [self setVideoAspectRatio:_fullScreenAspectRatio];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:DBChangeGammaSettingName])
        CGSetDisplayTransferByTable(kCGDirectMainDisplay, _savedTransferTables.sampleCount, _savedTransferTables.redTable, _savedTransferTables.greenTable, _savedTransferTables.blueTable);
    if (NSEnableScreenUpdates)   // available only on 10.3 and later
        NSEnableScreenUpdates();

    [NSCursor setHiddenUntilMouseMoves:NO];
}

- (void)mouseEntered:(NSEvent *)event
{
    if ([event trackingNumber] == _hotzoneTag && !_popUpActive) {
        [_popUpWindow makeKeyAndOrderFront:nil];
        [_popUpWindow setFrame:_popUpShowingFrame display:YES animate:YES];
        _popUpActive = YES;
    } else if ([event trackingNumber] == _popUpTag && _popUpActive) {
        [_popUpWindow setFrame:_popUpHiddenFrame display:YES animate:YES];
        [_popUpWindow orderOut:nil];
        _popUpActive = NO;
    }
}

- (void)mouseExited:(NSEvent *)event
{
}

- (IBAction)endFullScreen:(id)sender
{
    if ([self isFullScreen])
        [self endFullScreen];
    else
        NSBeep();
}

- (IBAction)toggleFullScreen:(id)sender
{
    if ([self isFullScreen])
        [self endFullScreen];
    else
        [self beginFullScreen];
}

- (BOOL)isFullScreen
{
    return _isFullScreen;
}

- (void)cursorHider:(NSTimer *)timer
{
    double secs = CGSSecondsSinceLastInputEvent();
    if ([self isFullScreen]) {
        UpdateSystemActivity(UsrActivity);	// prevent display dimming
        if (!_popUpActive && secs > 5.0)
            [NSCursor setHiddenUntilMouseMoves:YES];
    }
}

#pragma mark Aspect ratio

- (IBAction)takeVideoAspectRatioFrom:(id)sender
{
    [self setVideoAspectRatio:[sender tag]];
}

- (void)setVideoAspectRatio:(DBVidiAspectRatio)ratio;
{
    NSRect newFrame = [[self window] frame];
    float oldHeight;
    AspectRatioInfo *newRatio = _aspectRatios + ratio;

    if (![self isFullScreen]) {
        AspectRatioInfo *oldRatio = _aspectRatios + [[NSUserDefaults standardUserDefaults] integerForKey:DBAspectRatioSettingName];

        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:ratio] forKey:DBAspectRatioSettingName];
        [self updateNormalViewSizeAndCropping];

        newFrame.size.width = _borderWidth + (newFrame.size.width - _borderWidth) * newRatio->ratioWidth / oldRatio->ratioWidth;
        oldHeight = newFrame.size.height;
        newFrame.size.height = _borderHeight + (newFrame.size.height - _borderHeight) * newRatio->ratioHeight / oldRatio->ratioHeight;
        newFrame.origin.y += oldHeight - newFrame.size.height;
        [[self window] setFrame:newFrame display:YES];
    } else {
        _fullScreenAspectRatio = ratio;
        [self updateBigViewSizeAndCropping];
    }
}

#pragma mark NSSplitView delegate

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
{
    if (offset == 0)
        return 80;
    return proposedMin;
}

- (IBAction)showWindow:(id)sender;
{
    if ([self isFullScreen])
        [self endFullScreen];
    [super showWindow:sender];
}

- (IBAction)orderFrontMaskingPanel:(id)sender
{
    [maskingPanel makeKeyAndOrderFront:sender];
}

- (IBAction)takeMaskingTopFrom:(id)sender
{
    int masking = [sender intValue];

    [maskTopTextField setIntValue:masking];
    [maskTopStepper setIntValue:masking];
    [[NSUserDefaults standardUserDefaults] setInteger:masking forKey:DBMaskTopSettingName];
    [self updateNormalViewSizeAndCropping];
}

- (IBAction)takeMaskingBottomFrom:(id)sender
{
    int masking = [sender intValue];

    [maskBottomTextField setIntValue:masking];
    [maskBottomStepper setIntValue:masking];
    [[NSUserDefaults standardUserDefaults] setInteger:masking forKey:DBMaskBottomSettingName];
    [self updateNormalViewSizeAndCropping];
}

- (IBAction)takeMaskingLeftFrom:(id)sender
{
    int masking = [sender intValue];

    [maskLeftTextField setIntValue:masking];
    [maskLeftStepper setIntValue:masking];
    [[NSUserDefaults standardUserDefaults] setInteger:masking forKey:DBMaskLeftSettingName];
    [self updateNormalViewSizeAndCropping];
}

- (IBAction)takeMaskingRightFrom:(id)sender
{
    int masking = [sender intValue];

    [maskRightTextField setIntValue:masking];
    [maskRightStepper setIntValue:masking];
    [[NSUserDefaults standardUserDefaults] setInteger:masking forKey:DBMaskRightSettingName];
    [self updateNormalViewSizeAndCropping];
}

#pragma mark NSObject (NSWindowDelegate)

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    if ([[aNotification object] isEqual:_fullScreenWindow]) {
        if ([self isFullScreen])
            [self performSelector:@selector(endFullScreen) withObject:nil afterDelay:0];
    }
}

- (void)windowWillBeginSheet:(NSNotification *)aNotification
{
    if ([self isFullScreen])
        [self endFullScreen];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if ([self isFullScreen])
        [self endFullScreen];
    [channelsTable setDelegate:nil];
    [view setGrabber:nil];
    if (_cursorTimer)
        [_cursorTimer invalidate];
    if (_blinkerTimer)
        [_blinkerTimer invalidate];
    [self autorelease];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
    if (_borderWidth == 0)
        // not initialized yet. don't constrain
        return proposedFrameSize;

    AspectRatioInfo *aspectRatio = _aspectRatios + [[NSUserDefaults standardUserDefaults] integerForKey:DBAspectRatioSettingName];

    NSSize constrainedSize = { proposedFrameSize.width - _borderWidth, proposedFrameSize.height - _borderHeight };
    unsigned int modifierFlags = [[sender currentEvent] modifierFlags];
    if (modifierFlags & NSAlternateKeyMask) {
        constrainedSize.width += _normalViewSize.width / 8;
        constrainedSize.width -= (int)constrainedSize.width % (int)(_normalViewSize.width / 4);
        constrainedSize.height += _normalViewSize.height / 8;
        constrainedSize.height -= (int)constrainedSize.height % (int)(_normalViewSize.height / 4);
    }
    if (!(modifierFlags & NSShiftKeyMask) || (modifierFlags & NSAlternateKeyMask)) {
        if (constrainedSize.height > constrainedSize.width * aspectRatio->ratioHeight/aspectRatio->ratioWidth)
            constrainedSize.height = constrainedSize.width * aspectRatio->ratioHeight / aspectRatio->ratioWidth;
        else
            constrainedSize.width = constrainedSize.height * aspectRatio->ratioWidth / aspectRatio->ratioHeight;
    }
    constrainedSize.width += _borderWidth;
    constrainedSize.height += _borderHeight;
    return constrainedSize;
}

#pragma mark NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
    SEL action = [menuItem action];
    if (action == @selector(toggleHighQuality:)) {
        [menuItem setState:[_activeView highQuality]];
        return YES;
    }

    if (action == @selector(toggleSingleField:)) {
        [menuItem setState:[_activeView singleField]];
        return [_activeView highQuality];
    }

    if (action == @selector(toggleDeinterlace:)) {
        [menuItem setState:[_activeView deinterlace]];
        return [_activeView highQuality] && ![_activeView singleField];
    }

    if (action == @selector(takeVideoAspectRatioFrom:)) {
        DBVidiAspectRatio aspectRatio = (DBVidiAspectRatio)[[NSUserDefaults standardUserDefaults] integerForKey:DBAspectRatioSettingName];

        [menuItem setState:aspectRatio == [menuItem tag]];
        return [menuItem tag] != DBPALSquareAspectRatio || [[_vidi grabber] DVFormat] == DBPALFormat;
    }

    if (action == @selector(record:) && [_vidi isRecording])
        return NO;
    if (action == @selector(recordAs:) && [_vidi isRecording])
        return NO;
    if (action == @selector(stopRecording:) && ![_vidi isRecording])
        return NO;
    if (action == @selector(zoomWindow:))
        return ![self isFullScreen];
    if (action == @selector(toggleSettingsDrawer:)) {
        if (![self isFullScreen]) {
            [menuItem setTitle:[settingsDrawer state] == NSDrawerClosedState ? NSLocalizedString(@"Open Settings Drawer", nil) : NSLocalizedString(@"Close Settings Drawer", nil)];
            return _isFormac;
        } else
            return NO;
    }
    return YES;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    if ([self isFullScreen])
        [self endFullScreen];
}

@end
