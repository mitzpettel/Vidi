//
//  DBVidiWindowController.h
//  Vidi
//
//  Created by Mitz Pettel on Sat Feb 01 2003.
//  Copyright (c) 2003, 2004 Mitz Pettel. All rights reserved.
//

#import <AppKit/AppKit.h>

#import "DBMediumWindowController.h"


#define DBChangeGammaSettingName @"change gamma in full screen mode"
#define DBAspectRatioSettingName @"video aspect ratio"
#define DBHighQualitySettingName @"high quality"
#define DBDeinterlaceSettingName @"deinterlace"
#define DBSingleFieldSettingName @"single field"
#define DBMaskTopSettingName @"mask top"
#define DBMaskBottomSettingName @"mask bottom"
#define DBMaskLeftSettingName @"mask left"
#define DBMaskRightSettingName @"mask right"

@class DBDVView;

typedef enum {
    DB4to3AspectRatio = 0,
    DB16to9AspectRatio = 1,
    DBPALSquareAspectRatio = 2,
    DB16to9CropAspectRatio = 3
} DBVidiAspectRatio;

typedef struct {
    DBVidiAspectRatio	tag;
    int			clipWidthNum;
    int			clipWidthDenom;
    int			clipHeightNum;
    int			clipHeightDenom;
    int			ratioWidth;
    int			ratioHeight;
} AspectRatioInfo;

@class DBVidiWindow;

@interface DBVidiWindowController : DBMediumWindowController {
    IBOutlet NSTextField *channelNameTextField;
    IBOutlet NSPopUpButton *inputPopUp;
    IBOutlet NSImageView *logoEditableImageView;
    IBOutlet NSSlider *channelVolumeSlider;
    IBOutlet NSPopUpButton *callKeyPopUp;
    IBOutlet NSButton *settingsButton;

    IBOutlet NSSlider *brightnessSlider;
    IBOutlet NSSlider *contrastSlider;
    IBOutlet NSSlider *saturationSlider;
    IBOutlet NSView *hueControls;
    IBOutlet NSSlider *hueSlider;

    IBOutlet NSDrawer *settingsDrawer;
    IBOutlet DBDVView *view;

    IBOutlet NSView *popUp;

    IBOutlet NSImageView *channelLogoDisplay;
    IBOutlet NSTextField *channelNameDisplay;
    IBOutlet NSSlider *fullScrVolumeSlider;

    IBOutlet NSPanel *maskingPanel;

    IBOutlet NSStepper *maskTopStepper;
    IBOutlet NSStepper *maskBottomStepper;
    IBOutlet NSStepper *maskLeftStepper;
    IBOutlet NSStepper *maskRightStepper;

    IBOutlet NSTextField *maskTopTextField;
    IBOutlet NSTextField *maskBottomTextField;
    IBOutlet NSTextField *maskLeftTextField;
    IBOutlet NSTextField *maskRightTextField;

    NSWindow *_popUpWindow;
    DBVidiWindow *_fullScreenWindow;
    DBDVView *_bigDBDVView;
    DBVidiAspectRatio _fullScreenAspectRatio;

    NSTrackingRectTag _hotzoneTag;
    NSTrackingRectTag _popUpTag;
    NSRect _popUpHiddenFrame;
    NSRect _popUpShowingFrame;
    BOOL _popUpActive;

    BOOL _hasTuner;
    BOOL _isFormac;

    struct {
        CGGammaValue redTable[256];
        CGGammaValue greenTable[256];
        CGGammaValue blueTable[256];
        CGTableCount sampleCount;
    } _savedTransferTables;

    float _borderWidth;
    float _borderHeight;

    NSSize _normalViewSize;

    BOOL _isFullScreen;
    DBDVView *_activeView;

    NSTimer *_cursorTimer;
}

- (IBAction)toggleHighQuality:(id)sender;
- (IBAction)toggleSingleField:(id)sender;
- (IBAction)toggleDeinterlace:(id)sender;
- (IBAction)takeChannelNameFrom:(id)sender;
- (IBAction)takeChannelVolumeFrom:(id)sender;
- (IBAction)takeChannelLogoFrom:(id)sender;
- (IBAction)takeChannelCallKeyFrom:(id)sender;
- (IBAction)takeChannelInputFrom:(id)sender;
- (IBAction)pictureSettingsChanged:(id)sender;
- (IBAction)takeMaskingTopFrom:(id)sender;
- (IBAction)takeMaskingLeftFrom:(id)sender;
- (IBAction)takeMaskingBottomFrom:(id)sender;
- (IBAction)takeMaskingRightFrom:(id)sender;
- (IBAction)toggleSettingsDrawer:(id)sender;
- (IBAction)zoomWindow:(id)sender;

- (IBAction)endFullScreen:(id)sender;
- (IBAction)toggleFullScreen:(id)sender;

- (IBAction)orderFrontMaskingPanel:(id)sender;

- (IBAction)takeVideoAspectRatioFrom:(id)sender;

- (void)setVideoAspectRatio:(DBVidiAspectRatio)ratio;
- (BOOL)isFullScreen;
- (void)endFullScreen;
- (void)beginFullScreen;
- (void)updatePictureSliders;

@end
