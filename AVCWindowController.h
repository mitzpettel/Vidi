//
//  AVCWindowController.h
//  Vidi
//
//  Created by Mitz Pettel on Mar 28 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface AVCWindowController : NSWindowController
{
    IBOutlet NSButton *checkbox;
    IBOutlet NSTextField *cmd0;
    IBOutlet NSTextField *cmd1;
    IBOutlet NSTextField *cmd2;
    IBOutlet NSTextField *cmd3;
    IBOutlet NSTextField *cmd4;
    IBOutlet NSTextField *cmd5;
    IBOutlet NSTextField *cmd6;
    IBOutlet NSTextField *cmd7;
    IBOutlet NSTextField *response;
}

- (IBAction)send:(id)sender;

@end
