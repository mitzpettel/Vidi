//
//  DBButton.m
//  Vidi
//
//  Created by Mitz Pettel on Tue Jan 28 2003.
//  Copyright (c) 2002, 2003 Mitz Pettel. All rights reserved.
//

#import "DBButton.h"


@implementation DBButton

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    [NSApp preventWindowOrdering];
    [super mouseDown:theEvent];
}

@end
