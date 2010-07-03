//
//  DBTVRemoteControl.m
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 29 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBTVRemoteControl.h"

#import "DBMediumWindowController.h"
#import "DBVidi.h"

@implementation DBTVRemoteControl

- (void)keyDown:(NSEvent *)event
{
    NSString *chars = [event characters];
    unichar keyChar = [chars characterAtIndex:0];
    unsigned int modifierFlags = [event modifierFlags];
    DBVidi *vidi = [controller vidi];

    switch (keyChar)
    {
        case '\E': // escape
            [NSApp sendAction:@selector(endFullScreen:) to:nil from:self];
            break;
        case NSEnterCharacter:
            if (![vidi isRecording])
                [vidi flipChannels];
            break;
    	case NSRightArrowFunctionKey:
            if (![vidi isRecording])
                [vidi selectNextChannel];
            break;
    	case NSLeftArrowFunctionKey:
            if (![vidi isRecording])
                [vidi selectPreviousChannel];
            break;
    	case NSUpArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [vidi setVolume:2.0];
            else
                [vidi setVolume:MIN(2.0, [vidi volume] + 0.125)];
            break;
    	case NSDownArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask)
                [vidi setVolume:0.0];
            else
                [vidi setVolume:MAX(0.0, [vidi volume] - 0.125)];
            break;
        default:
            if (modifierFlags & NSNumericPadKeyMask) {
                if (keyChar == '0')
                    [vidi setMuted:![vidi isMuted]];
                else if (keyChar > '0' && keyChar <= '9'  && ![vidi isRecording]) {
                    if (modifierFlags & NSShiftKeyMask)
                        [vidi setCallKey:keyChar-'0' forChannel:[vidi selectedChannel]];
                    else if ([vidi channelWithCallKey:keyChar - '0'])
                        [vidi selectChannel:[vidi channelWithCallKey:keyChar-'0']];
                }
            } else
                [super keyDown:event];
            break;
    }
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)setController:(DBMediumWindowController *)newController
{
    controller = newController;
}

@end
