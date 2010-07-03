//
//  DBTVChannel.h
//  Vidi
//
//  Created by Mitz Pettel on Sun Jan 26 2003.
//  Copyright (c) 2002, 2003 Mitz Pettel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DBDVGrabber.h"


extern NSString * const DBTVChannelChangedNotification;

@interface DBTVChannel : NSObject {
    DBTVFrequency _frequency;
    NSString *_name;
    float _volume;
    NSImage *_logo;
    DBDVInputSource _inputSource;
}

+ (id)channelWithFrequency:(DBTVFrequency)freq inputSource:(DBDVInputSource)source name:(NSString *)string volume:(float)vol logo:(NSImage *)image;

+ (id)channelWithFrequency:(DBTVFrequency)freq;

+ (id)channelWithDictionary:(NSDictionary *)dict;

// Designated initializer
- (id)initWithFrequency:(DBTVFrequency)freq inputSource:(DBDVInputSource)source name:(NSString *)string volume:(float)vol logo:(NSImage *)image;

- (id)initWithFrequency:(DBTVFrequency)freq;

- (id)initWithDictionary:(NSDictionary *)dict;

- (NSDictionary *)dictionary;
- (NSDictionary *)dictionaryWithoutLogo;

- (void)setFrequency:(DBTVFrequency)freq;
- (DBTVFrequency)frequency;

- (void)setName:(NSString *)string;
- (NSString *)name;

- (void)setVolume:(float)vol;
- (float)volume;

- (void)setLogo:(NSImage *)image;
- (NSImage *)logo;

- (void)setInputSource:(DBDVInputSource)source;
- (DBDVInputSource)inputSource;

- (void)_sendChangeNotification;

@end
