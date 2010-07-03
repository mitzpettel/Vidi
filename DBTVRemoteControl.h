//
//  DBTVRemoteControl.h
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 29 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class DBMediumWindowController;

@interface DBTVRemoteControl : NSView {
    IBOutlet DBMediumWindowController *controller;
}

- (void)setController:(DBMediumWindowController *)newController;

@end
