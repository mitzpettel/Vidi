//
//  DBAudioCompression.h
//  Vidi
//
//  Created by Mitz Pettel on Sat Jul 26 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DBAudioCompression : NSObject {

}

+ (NSDictionary *)runStandardSoundCompressionDialogWithFormat:(NSDictionary *)initialFormat;

+ (NSString *)descriptionOfFormat:(NSDictionary *)audioFormat;

@end
