//
//  server_main.m
//  Vidi
//
//  Created by Mitz Pettel on Mar 15 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DBVidiServer.h"

int main(int argc, const char *argv[])
{

    id	server;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    [[NSUserDefaults standardUserDefaults] addSuiteNamed:@"com.mitzpettel.Vidi"];
    [NSApplication sharedApplication];

//    [NSApp activateIgnoringOtherApps:YES];
//    NSRunAlertPanel(@"Alert", @"I have something to say", @"Shut Up", nil, nil);
    server = [DBVidiServer new];
    if (server)
    {
        [NSApp setDelegate:server];
        [NSApp run];
        [pool release];
        return 0;
    }
    else
        NSLog(@"Could not register.");
    return 1;
}
