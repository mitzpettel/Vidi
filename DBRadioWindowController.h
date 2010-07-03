//
//  DBRadioWindowController.h
//  Vidi
//
//  Created by Mitz Pettel on Feb 22 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DBMediumWindowController.h"

@interface DBRadioWindowController : DBMediumWindowController
{
    IBOutlet NSView *editModeView;
    
    BOOL _isInEditMode;
    DBTVChannel *_temporaryChannel;
}

- (IBAction)editChannelName:(id)sender;

@end
