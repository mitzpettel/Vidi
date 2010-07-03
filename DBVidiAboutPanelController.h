//
//  DBVidiAboutPanelController.h
//  Vidi
//
//  Created by Mitz Pettel on Mar 28 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface DBVidiAboutPanelController : NSObject
{
    IBOutlet id appIconView;
    IBOutlet id appNameField;
    IBOutlet id infoPanel;
    IBOutlet id legalTextField;
    IBOutlet id tunerTextField;
    IBOutlet id versionField;
}

+ (id)sharedAboutPanelController;

- (IBAction)showPanel:(id)sender;

- (NSString *)hardwareInfoString;

@end
