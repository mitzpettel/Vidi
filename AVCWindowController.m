//
//  AVCWindowController.m
//  Vidi
//
//  Created by Mitz Pettel on Mar 28 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "AVCWindowController.h"
#import "DBVidi.h"

@implementation AVCWindowController

- (int)valueFromField:(NSTextField *)field
{
    int value;
    NSString *string = [field stringValue];
    sscanf( [string cString], "%x", &value );
    return value;
}

- (IBAction)send:(id)sender
{
    DBDVGrabber *grabber = [(DBVidi *)[NSApp delegate] grabber];
    UInt8 cmd[8];
    UInt8 rsp[8];
    int size = 8;
    int len = ([checkbox state] ? 8 : 4);
    cmd[0] = [self valueFromField:cmd0];
    cmd[1] = [self valueFromField:cmd1];
    cmd[2] = [self valueFromField:cmd2];
    cmd[3] = [self valueFromField:cmd3];
    cmd[4] = [self valueFromField:cmd4];
    cmd[5] = [self valueFromField:cmd5];
    cmd[6] = [self valueFromField:cmd6];
    cmd[7] = [self valueFromField:cmd7];
    [grabber doAVCCommand:cmd length:len response:rsp size:&size];
    [response setStringValue:[NSString stringWithFormat:@"%x %x %x %x", rsp[0], rsp[1], rsp[2], rsp[3]]];
}

@end
