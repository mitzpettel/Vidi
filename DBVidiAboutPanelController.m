//
//  DBVidiAboutPanelController.m
//  Vidi
//
//  Created by Mitz Pettel on Mar 28 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBVidiAboutPanelController.h"
#import "DBVidi.h"

@implementation DBVidiAboutPanelController

+ (id)sharedAboutPanelController {
    static DBVidiAboutPanelController *sharedInstance = nil;
    
    if (!sharedInstance) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id)init {
    NSBundle	*bundle;
    
    self = [super init];
    if (self) {
        [NSBundle loadNibNamed:@"AboutPanel" owner:self];
    }
    bundle = [NSBundle mainBundle];
    [appNameField setStringValue:[bundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey]];
    [legalTextField setStringValue:[bundle objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];
    [tunerTextField
        setStringValue:[self hardwareInfoString]
    ];
    [versionField
        setStringValue:[NSString
            stringWithFormat:@"%@ (v%@)",
            [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
            [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey]
        ]
    ];
    return self;
}

- (NSString *)firmwareVersionString
{
    unsigned	firmwareVersion = [[NSApp delegate] firmwareVersion];
    return [NSString
        stringWithFormat:@"%d.%d.%d",
        (firmwareVersion >>24) & 0xFF,
        (firmwareVersion >>16) & 0xFF,
        (firmwareVersion >>8)  & 0xFF
    ];
}

- (NSString *)hardwareInfoString
{
    if ( [[NSApp delegate] firmwareVersion]==0 )
        return NSLocalizedString( @"Generic DV device", @"hardware info in About Vidi" );
    if ( [[NSApp delegate] tunerDisplayName] )
        return [NSString
            stringWithFormat:NSLocalizedString( @"Formac Studio DV/TV (%@)\nTuner: %@", @"hardware info in About Vidi. parameters are frimware version and tuner model" ),
            [self firmwareVersionString],
            [[NSApp delegate] tunerDisplayName]
        ];
    return [NSString
        stringWithFormat:NSLocalizedString( @"Formac Studio DV (%@)", @"hardware info in About Vidi. parameter is frimware version" ),
        [self firmwareVersionString]
    ];
}

- (void)dealloc
{
    [infoPanel release];
    [super dealloc];
}

- (IBAction)showPanel:(id)sender
{
    if ( ![infoPanel isVisible] )
        [infoPanel center];
    [infoPanel makeKeyAndOrderFront:nil];
}

@end
