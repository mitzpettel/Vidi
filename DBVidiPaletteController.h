//
//  DBVidiPaletteController.h
//  Vidi
//
//  Created by Mitz Pettel on Sun Feb 23 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class DBVidiServer;

@interface DBVidiPaletteController : NSWindowController {
    IBOutlet NSSlider *contrastSlider;
    IBOutlet NSSlider *brightnessSlider;
    IBOutlet NSSlider *saturationSlider;
    IBOutlet NSSlider *hueSlider;
    IBOutlet NSView *hueControls;
    IBOutlet NSPopUpButton *channelPopUp;

    DBVidiServer *_server;
    NSMutableArray *_channels;
    BOOL _hueControlsVisible;
}

- (id)initWithServer:(DBVidiServer *)server;
- (IBAction)pictureSettingsChanged:(id)sender;
- (IBAction)takeChannelFrom:(id)sender;
- (void)setHueControlsVisible:(BOOL)visible;
- (void)readUserDefaults;

@end
