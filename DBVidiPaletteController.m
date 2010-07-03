//
//  DBVidiPaletteController.m
//  Vidi
//
//  Created by Mitz Pettel on Sun Feb 23 2003.
//  Copyright (c) 2003, 2007 Mitz Pettel. All rights reserved.
//

#import "DBVidiPaletteController.h"

#import "DBTVChannel.h"
#import "DBVidiServer.h"


@implementation DBVidiPaletteController

- (id)initWithServer:(DBVidiServer *)server
{
    _server = server;
    self = [super initWithWindowNibName:@"Palette"];
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self setShouldCascadeWindows:NO];
    [self setWindowFrameAutosaveName:@"palette"];
    [[self window] setHidesOnDeactivate:NO];
    [(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
    [hueControls retain];	// never released;
    _hueControlsVisible = YES;
}

- (void)readUserDefaults
{
    NSDictionary *currentChannel;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSArray *channelPlist = [defs objectForKey:DBTVChannelsKey];
    NSMenu *channelMenu = [[NSMenu new] autorelease];
    NSEnumerator *enumerator;
    DBTVChannel *channel;
    int b;
    int c;
    int s;
    int h;
    BOOL hasTuner = [[_server grabber] hasTuner];

    [self window];	// force loading

    [defs synchronize];

    if (channelPlist == nil || !hasTuner) {
        _channels = [NSMutableArray new];
        [_channels insertObject:[DBTVChannel channelWithFrequency:0 inputSource:DBCompositeInput name:NSLocalizedStringFromTable(@"Composite", @"server", @"name for auto-generated channel") volume:1.0 logo:nil] atIndex:0];
        [_channels insertObject:[DBTVChannel channelWithFrequency:0 inputSource:DBSVideoInput name:NSLocalizedStringFromTable(@"S-Video", @"server", @"name for auto-generated channel") volume:1.0 logo:nil] atIndex:1];
    } else {
        _channels = [NSMutableArray new];
        enumerator = [channelPlist objectEnumerator];
        while (currentChannel = [enumerator nextObject])
            [_channels addObject:[DBTVChannel channelWithDictionary:currentChannel]];
    }
    enumerator = [_channels objectEnumerator];
    while (channel = [enumerator nextObject])
        [channelMenu addItemWithTitle:[channel name] action:nil keyEquivalent:@""];
    [channelPopUp setMenu:channelMenu];
    [channelPopUp selectItemAtIndex:MIN([defs integerForKey:DBTVChannelSettingName], [_channels count] - 1)];
    [self takeChannelFrom:channelPopUp];

    b = [defs integerForKey:DBBrightnessSettingName];
    c = [defs integerForKey:DBContrastSettingName];
    s = [defs integerForKey:DBSaturationSettingName];
    h = [defs integerForKey:DBHueSettingName];
    [brightnessSlider setIntValue:b];
    [contrastSlider setIntValue:c];
    [saturationSlider setIntValue:s];
    [hueSlider setIntValue:h];
}

- (void)setHueControlsVisible:(BOOL)visible
{
    if (_hueControlsVisible != visible) {
        NSRect frame = [[self window] frame];
        if (visible) {
            frame.size.height += [hueControls frame].size.height;
            [[self window] setFrame:frame display:YES];
            [[[self window] contentView] addSubview:hueControls];
        } else {
            frame.size.height -= [hueControls frame].size.height;
            [hueControls removeFromSuperview];
            [[self window] setFrame:frame display:YES];
        }

        _hueControlsVisible = visible;
    }
}

- (IBAction)takeChannelFrom:(id)sender
{
    int i;
    DBTVChannel *chan;

    i = [sender indexOfSelectedItem];
    chan = [_channels objectAtIndex:i];
    [_server setChannelDictionary:[chan dictionary]];
    CFPreferencesSetValue(CFSTR("channel"), [NSNumber numberWithInt:i], CFSTR("com.mitzpettel.Vidi"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)pictureSettingsChanged:(id)sender
{
    int b = [brightnessSlider intValue];
    int c = [contrastSlider intValue];
    int s = [saturationSlider intValue];
    int h = [hueSlider intValue];

    [[_server grabber] setBrightness:b contrast:c saturation:s hue:h];

    CFPreferencesSetValue(CFSTR("brightness"), [NSNumber numberWithInt:b], CFSTR("com.mitzpettel.Vidi"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue(CFSTR("contrast"), [NSNumber numberWithInt:c], CFSTR("com.mitzpettel.Vidi"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue(CFSTR("saturation"), [NSNumber numberWithInt:s], CFSTR("com.mitzpettel.Vidi"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue (CFSTR("hue"), [NSNumber numberWithInt:h], CFSTR("com.mitzpettel.Vidi"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
