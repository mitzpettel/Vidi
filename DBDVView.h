//
//  DBDVView.h
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 22 2003.
//  Copyright (c) 2003, 2005 Mitz Pettel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <QuickTime/QuickTime.h>


#define	DBDVViewUnknownDVFromatException	@"DBDVViewUnknownDVFromatException"

@class DBDVGrabber;
@protocol DBDVGrabber;
struct DBDVGrabberSharedMemory;

@interface DBDVView : NSOpenGLView
{
    ImageSequence _decompSeq;
    GWorldPtr _gWorld;
    GWorldPtr dragGWorld;
    GLenum _textureType;
    void *_pixels;
    void *dragPixels;
    DBDVGrabber *_grabber;
    int _sharedMemoryFile;
    struct DBDVGrabberSharedMemory *_sharedMemory;
    int _sharedMemorySize;
    NSLock *_painterLock;
    int _painterThreads;
    NSLock *_decompLock;
    BOOL _highQuality;
    BOOL _singleField;
    BOOL _deinterlace;
    NSImage *_dragResizeImage;
    NSQuickDrawView *_imageQDView;
    ImageSequence _imageDS;
    BOOL _fullScreen;
    int _DVFrameWidth;
    int _DVFrameHeight;
    int _DVFrameDataSize;
    CodecType _DVFrameIMDC;
    int _numOverpainted;

    int _maskBottom;
    int _maskTop;
    int _maskLeft;
    int _maskRight;
    int _borderBottom;
    int _borderTop;
    int _borderLeft;
    int _borderRight;

    BOOL _isLogging;
}

-(ComponentResult)setupDecompSeq;
-(ComponentResult)setupDecompSeq:(ImageSequence *)seq view:(NSQuickDrawView *)aView highQuality:(BOOL)hq;
-(ComponentResult)setupDecompSeq:(ImageSequence *)seq port:(CGrafPtr)grafPort highQuality:(BOOL)hq;

-(ComponentResult)decompToWindow;
-(void)setHighQuality:(BOOL)flag;
-(BOOL)highQuality;
-(void)setSingleField:(BOOL)flag;
-(BOOL)singleField;
-(void)setDeinterlace:(BOOL)flag;
-(BOOL)deinterlace;
-(NSImage *)currentImage;
-(void)setGrabber:(id <DBDVGrabber>)grab;
-(void)setFullScreen:(BOOL)flag;
- (NSSize)DVFrameSize;
- (void)setCroppingTop:(int)t left:(int)l bottom:(int)b right:(int)r;
- (void)setBorderTop:(int)t left:(int)l bottom:(int)b right:(int)r;

@end
