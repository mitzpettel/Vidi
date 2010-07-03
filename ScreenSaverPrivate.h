/*
 *  ScreenSaverPrivate.h
 *
 *  Created by Mitz Pettel on Sat Aug 17 2002.
//  Copyright (c) 2002 Mitz Pettel <source@mitzpettel.com>. All rights reserved.
//

 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <Foundation/Foundation.h>

@protocol ScreenSaverControl
- (double)screenSaverTimeRemaining;
- (void)restartForUser:fp16;
- (void)screenSaverStopNow;
- (void)screenSaverStartNow;
- (void)setScreenSaverCanRun:(char)fp19;
- (char)screenSaverCanRun;
- (char)screenSaverIsRunning;
@end

@interface ScreenSaverController:NSObject <ScreenSaverControl>
{
    NSConnection *_connection;
    id _daemonProxy;
    void *_reserved;
}

+ controller;
+ monitor;
+ daemonConnectionName;
+ daemonPath;
+ enginePath;
- init;
- (void)dealloc;
- (void)_connectionClosed:fp12;
- (char)screenSaverIsRunning;
- (char)screenSaverCanRun;
- (void)setScreenSaverCanRun:(char)fp12;
- (void)screenSaverStartNow;
- (void)screenSaverStopNow;
- (void)restartForUser:fp12;
- (double)screenSaverTimeRemaining;

@end
