//
//  DBDVView.m
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 22 2003.
//  Copyright (c) 2003, 2005, 2006 Mitz Pettel. All rights reserved.
//


#import "DBDVView.h"

#import "DBDVGrabber.h"
#import <OpenGL/glu.h>
#import <QuickTime/QuickTime.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <unistd.h>

#define MAX_TILE 128

#if __BIG_ENDIAN__
#define ARGB_IMAGE_TYPE GL_UNSIGNED_SHORT_8_8_REV_APPLE
#else
#define ARGB_IMAGE_TYPE GL_UNSIGNED_SHORT_8_8_APPLE
#endif

@implementation DBDVView

+ (NSOpenGLPixelFormat *)defaultPixelFormat
{
    NSOpenGLPixelFormatAttribute attrib[] = { NSOpenGLPFADoubleBuffer, NSOpenGLPFAWindow, (NSOpenGLPixelFormatAttribute)NULL };
    return [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrib] autorelease];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return !_fullScreen;
}

-(id)initWithFrame:(NSRect)frameRect
{
    long swapInterval = 1;

    self = [super initWithFrame:frameRect pixelFormat:[[self class] defaultPixelFormat]];
    _painterLock = [[NSLock alloc] init];
    _painterThreads = 0; // should never be > 1
    _decompLock = [[NSLock alloc] init];
    _fullScreen = NO;
    _isLogging = [[NSUserDefaults standardUserDefaults] boolForKey:@"DBVidiLog"];
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];

    _textureType = GL_TEXTURE_RECTANGLE_EXT;
    return self;
}

-(void)setFullScreen:(BOOL)flag
{
    _fullScreen = flag;
}

-(void)setGrabber:(id <DBDVGrabber>)grab
{
    DBDVFormat DVFormat;
    if (_isLogging)
        NSLog(@"-[DBDVView setGrabber:0x%x]", grab);
    [_grabber autorelease];
    _grabber = [(DBDVGrabber *)grab retain];
    [_painterLock lock];
    DVFormat = [_grabber DVFormat];
    if (_isLogging)
        NSLog(@"DVFormat: %d", DVFormat);
    if (DVFormat == DBPALFormat) {
        _DVFrameWidth = 720;
        _DVFrameHeight = 576;
        _DVFrameDataSize = 144000;
        _DVFrameIMDC = 'dvcp';
    } else if (DVFormat == DBNTSCFormat) {
        _DVFrameWidth = 720;
        _DVFrameHeight = 480;
        _DVFrameDataSize = 120000;
        _DVFrameIMDC = 'dvc ';
    } else
        [NSException raise:DBDVViewUnknownDVFromatException format:@"Unknown DV format."];

    [_decompLock lock];
        if (_isLogging)
            NSLog(@"_decompLock locked");
        if (_decompSeq) {
            if (_isLogging)
                NSLog(@"_decompSeq exists");
            CDSequenceEnd(_decompSeq); //crashes us!
            if (_isLogging)
                NSLog(@"_decompSeq ended");
        }
        _decompSeq = nil;
        if (_gWorld)
            DisposeGWorld(_gWorld);
        _gWorld = 0;
        if (dragGWorld)
            DisposeGWorld(dragGWorld);
        dragGWorld = 0;
        if (_grabber) {
            Rect bounds = { 0, 0, _DVFrameHeight, _DVFrameWidth + 16 };
            int i;

            if (_pixels == NULL)
                    _pixels = malloc(_DVFrameHeight * (_textureType == GL_TEXTURE_RECTANGLE_EXT ? 2 : 4) * (_DVFrameWidth + 16)); // FIXME: use vm_alloc

            // FIXME: Why are we doing this?
            for (i = 0; i < _DVFrameHeight * (_textureType == GL_TEXTURE_RECTANGLE_EXT ? 2 : 4) * (_DVFrameWidth + 16); i += 4)
                    *(unsigned long *)(_pixels+i) = 0x70007000;

            QTNewGWorldFromPtr(&_gWorld, (_textureType == GL_TEXTURE_RECTANGLE_EXT ? k2vuyPixelFormat : k32ARGBPixelFormat), &bounds, nil, nil, 0, _pixels, (_textureType == GL_TEXTURE_RECTANGLE_EXT ? 2 : 4) * (_DVFrameWidth + 16));
            QTSetPixMapHandleRequestedGammaLevel(GetPortPixMap(_gWorld), kQTUsePlatformDefaultGammaLevel);
            [self setupDecompSeq];
            [[self openGLContext] makeCurrentContext];
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
            glEnable(_textureType);
            if (_textureType == GL_TEXTURE_RECTANGLE_EXT) {
                glBindTexture(_textureType, 1);
                glTextureRangeAPPLE(_textureType, _DVFrameHeight * 2 * (_DVFrameWidth + 16), _pixels);
                glTexParameteri(_textureType, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
                glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
                glTexParameteri(_textureType, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                glTexParameteri(_textureType, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(_textureType, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameteri(_textureType, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                glPixelStorei(GL_UNPACK_ROW_LENGTH , 0);
                glTexImage2D(_textureType, 0, GL_RGBA, _DVFrameWidth + 16, _DVFrameHeight, 0, GL_YCBCR_422_APPLE, ARGB_IMAGE_TYPE, _pixels);
            } else {
                int top = 0;
                int height = MAX_TILE;
                int textureNumber = 1;

                glPixelStorei(GL_UNPACK_ROW_LENGTH , _DVFrameWidth);
                while (top < _DVFrameHeight) {
                    int left = 0;
                    int width = MAX_TILE;
                    if (height > _DVFrameHeight - top) {
                        height = _DVFrameHeight - top;
                        int i = MAX_TILE / 2;
                        while (!(height & i))
                            i /= 2;
                        height = i;
                    }

                    while (left < _DVFrameWidth) {
                        if (width > _DVFrameWidth - left) {
                            width = _DVFrameWidth - left;
                            int i = MAX_TILE / 2;
                            while (!(width & i))
                                i /= 2;
                            width = i;
                        }
                        glBindTexture(_textureType, textureNumber);
                        glTextureRangeAPPLE(_textureType, _DVFrameHeight * 2 * _DVFrameWidth, _pixels);
                        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
                        glTexParameteri(_textureType, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
                        glTexParameteri(_textureType, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                        glTexParameteri(_textureType, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                        glTexParameteri(_textureType, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                        glTexParameteri(_textureType, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                        glPixelStorei(GL_UNPACK_ROW_LENGTH , _DVFrameWidth + 16);
                        glTexImage2D( _textureType, 0, GL_RGBA, MAX_TILE, MAX_TILE, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _pixels);
                        textureNumber++;
                        left += width;
                    }
                    top += height;
                }
            }
        }

        if (_isLogging)
            NSLog(@"_decompSeq: 0x%x", _decompSeq);
    [_decompLock unlock];
    if (_isLogging)
        NSLog( @"_decompLock unlocked" );
    
    [self setSingleField:_singleField];
    [self setDeinterlace:_deinterlace];

    if (_dragResizeImage) {
        [_dragResizeImage release];
        [_imageQDView release];
    }
    _dragResizeImage = nil;
    if (_imageDS)
        CDSequenceEnd(_imageDS);
    _imageDS = nil;

    if (_grabber) {        
        Rect bounds = { 0, 0, _DVFrameHeight, _DVFrameWidth };
        unsigned char *pixels;
        NSBitmapImageRep *imageRep;

        _sharedMemoryFile = shm_open("com.mitzpettel.Vidi.mem", O_RDWR, 0666);
        _sharedMemorySize = sizeof(DBDVGrabberSharedMemory) + [_grabber bufferCount] * (_DVFrameDataSize + sizeof(DBDVFrameInfo));
        _sharedMemory = mmap(0, _sharedMemorySize, PROT_READ|PROT_WRITE, MAP_FILE | MAP_SHARED, _sharedMemoryFile, 0);
        if (_isLogging)
            NSLog(@"_sharedMemory: 0x%x", _sharedMemory);

        if (dragPixels == NULL)
            dragPixels = malloc(_DVFrameHeight * 4 * _DVFrameWidth + 1);  // FIXME: use vm_alloc
        QTNewGWorldFromPtr(&dragGWorld, k32ARGBPixelFormat, &bounds, nil, nil, 0, dragPixels, 4 * _DVFrameWidth);

        _dragResizeImage = [[NSImage alloc] initWithSize:NSMakeSize(_DVFrameWidth, _DVFrameHeight)];

        pixels = ((unsigned char *)dragPixels) + 1;
        imageRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&pixels pixelsWide:_DVFrameWidth pixelsHigh:_DVFrameHeight bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:_DVFrameWidth * 4 bitsPerPixel:32] autorelease];
        [_dragResizeImage addRepresentation:imageRep];

        [self setupDecompSeq:&_imageDS port:dragGWorld highQuality:YES];

        if (_painterThreads == 0)
            [NSApplication detachDrawingThread:@selector(painter:) toTarget:self withObject:nil];
    } else {
        if (_sharedMemory)
            munmap(_sharedMemory, _sharedMemorySize);
        _sharedMemory = NULL;

        if (_sharedMemoryFile)
            close(_sharedMemoryFile);
        _sharedMemoryFile = 0;
    }
    [_painterLock unlock];

    if (_isLogging)
        NSLog( @"-[DBDVView setGrabber:] finished" );
}

- (NSSize)DVFrameSize
{
    return NSMakeSize(_DVFrameWidth, _DVFrameHeight);
}

-(void)setHighQuality:(BOOL)flag
{
    _highQuality = flag;
    [_decompLock lock];
        if (_decompSeq)
            SetDSequenceAccuracy(_decompSeq, (_highQuality ? codecLosslessQuality : codecNormalQuality));
    [_decompLock unlock];
}

-(void)setSingleField:(BOOL)flag
{
    _singleField = flag;
    [_decompLock lock];
        if (_decompSeq)
            SetDSequenceFlags(_decompSeq, (_singleField ? codecDSequenceSingleField : 0 ), codecDSequenceSingleField);
    [_decompLock unlock];
}

-(void)setDeinterlace:(BOOL)flag
{
    _deinterlace = flag;
    [_decompLock lock];
        if ( _decompSeq )
            SetDSequenceFlags(_decompSeq, (_deinterlace ? 0x0400 : 0), 0x0400);
    [_decompLock unlock];
}

- (BOOL)highQuality
{
    return _highQuality;
}

- (BOOL)singleField
{
    return _singleField;
}

- (BOOL)deinterlace
{
    return _deinterlace;
}

-(void)dealloc
{
    [self setGrabber:nil];
    [_painterLock release];
    [_decompLock release];
    if (_pixels)
        free(_pixels);
    if (dragPixels)
        free(dragPixels);
    [super dealloc];
}

- (void)setCroppingTop:(int)t left:(int)l bottom:(int)b right:(int)r
{
    _maskTop = t;
    _maskLeft = l;
    _maskBottom = b;
    _maskRight = r;
}

- (void)setBorderTop:(int)t left:(int)l bottom:(int)b right:(int)r
{
    _borderTop = t;
    _borderLeft = l;
    _borderBottom = b;
    _borderRight = r;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [[self openGLContext] makeCurrentContext];
    glViewport(0, 0, (int)newSize.width, (int)newSize.height);
}

- (void)_updateImage
{
    void *shmCPF = (void *)_sharedMemory->currentlyPlayingFrame;
    if (!shmCPF)
        return;

    ComponentResult err = noErr;
    CodecFlags ignore;
    DBDVFrameInfoPtr playing;
    const void *playingFrame;

    playing = (void *)_sharedMemory + (shmCPF - _sharedMemory->baseAddress);
    playingFrame = (void *)_sharedMemory + ((void *)playing->frameBuffer - _sharedMemory->baseAddress);

    if (playing)
        err = DecompressSequenceFrameWhen(_imageDS, (void *)playingFrame, _DVFrameDataSize, 0, &ignore, NULL, 0);
}

-(ComponentResult)setupDecompSeq
{
    return [self setupDecompSeq:&_decompSeq port:_gWorld highQuality:_highQuality];
}

-(ComponentResult)setupDecompSeq:(ImageSequence *)seq view:(NSQuickDrawView *)aView highQuality:(BOOL)hq
{
    ComponentResult result;

    [aView lockFocus];
        result = [self setupDecompSeq:seq port:[aView qdPort] highQuality:hq];
    [aView unlockFocus];
    return result;
}

-(ComponentResult)setupDecompSeq:(ImageSequence *)seq port:(CGrafPtr)grafPort highQuality:(BOOL)hq;
{
    ComponentResult err = noErr;
    Rect sourceRect = { 0, 0 };
    MatrixRecord scaleMatrix;	
    ImageDescriptionHandle imageDesc = (ImageDescriptionHandle)NewHandle(sizeof(ImageDescription));

    (**imageDesc).idSize = sizeof(ImageDescription);
    (**imageDesc).cType = _DVFrameIMDC;
    (**imageDesc).resvd1 = 0;
    (**imageDesc).resvd2 = 0;
    (**imageDesc).dataRefIndex = 0;
    (**imageDesc).version = 3;
    (**imageDesc).revisionLevel = 47;
    (**imageDesc).vendor = 'appl';
    (**imageDesc).temporalQuality = 0;
    (**imageDesc).spatialQuality = 1023;
    (**imageDesc).width = _DVFrameWidth;
    (**imageDesc).height = _DVFrameHeight;
    (**imageDesc).hRes = 4718592;
    (**imageDesc).vRes = 4718592;
    (**imageDesc).dataSize = _DVFrameDataSize;
    (**imageDesc).frameCount = 1;
    (**imageDesc).depth = 24;
    (**imageDesc).clutID = -1;
    
    sourceRect.right = (**imageDesc).width;
    sourceRect.bottom = (**imageDesc).height;
    SetIdentityMatrix(&scaleMatrix);

    err = DecompressSequenceBegin(seq, imageDesc, grafPort, NULL, NULL, &scaleMatrix, srcCopy, NULL, 0, (hq ? codecLosslessQuality : codecNormalQuality), bestSpeedCodec);
    DisposeHandle((Handle)imageDesc);
    return err;
}

-(ComponentResult)decompToWindow
{
    ComponentResult err = noErr;
    CodecFlags ignore;
    DBDVFrameInfoPtr playing;
    const void *playingFrame;
    void *shmCPF = (void *)_sharedMemory->currentlyPlayingFrame;

    if (shmCPF) {
        playing = (void *)_sharedMemory + (shmCPF - _sharedMemory->baseAddress);
        playingFrame = (void *)_sharedMemory + ((void *)playing->frameBuffer - _sharedMemory->baseAddress);
        if (playingFrame) {
            if ([_decompLock tryLock]) {
                playing->timesPainted++;
                err = DecompressSequenceFrameWhen(_decompSeq, (void *)playingFrame, _DVFrameDataSize, 0, &ignore, NULL, 0);
                [[self openGLContext] makeCurrentContext];
                glClear(GL_COLOR_BUFFER_BIT);
                glMatrixMode(GL_MODELVIEW);
                glLoadIdentity();
                glTranslatef(-1.0, -1.0, 0.0);
                glScalef(2.0 / _DVFrameWidth, 2.0 / _DVFrameHeight, 1.0);
                if (_textureType == GL_TEXTURE_RECTANGLE_EXT) {
                    glBindTexture(_textureType, 1);
                    glTexSubImage2D(_textureType, 0, 0, 0, _DVFrameWidth + 16, _DVFrameHeight, GL_YCBCR_422_APPLE, ARGB_IMAGE_TYPE, _pixels);
                    glBegin(GL_QUADS);
                        glColor3f(1.0, 1.0, 1.0);
                        
                        glTexCoord2i(_maskLeft, _DVFrameHeight - _maskBottom);
                        glVertex2i(_borderLeft, _borderBottom);

                        glTexCoord2i(_DVFrameWidth - _maskRight, _DVFrameHeight - _maskBottom);
                        glVertex2i(_DVFrameWidth - _borderRight, _borderBottom);

                        glTexCoord2i(_DVFrameWidth - _maskRight, _maskTop);
                        glVertex2i(_DVFrameWidth - _borderRight, _DVFrameHeight - _borderTop);
                        
                        glTexCoord2i(_maskLeft, _maskTop);
                        glVertex2i(_borderLeft, _DVFrameHeight - _borderTop);
                    glEnd();
                } else {
                    int top = 0;
                    int height = MAX_TILE;
                    int textureNumber = 1;

                    glMatrixMode(GL_TEXTURE);
                    glLoadIdentity();
                    glScalef(1.0 / MAX_TILE, 1.0 / MAX_TILE, 1.0);

                    while (top < _DVFrameHeight - _borderTop) {
                        int left = 0;
                        int width = MAX_TILE;
                        if (height > _DVFrameHeight - top)
                            height = _DVFrameHeight - top;

                        while (left < _DVFrameWidth - _borderRight) {
                            if (width > _DVFrameWidth - left)
                                width = _DVFrameWidth - left;
                            glBindTexture(_textureType, textureNumber);
                            glTexSubImage2D(_textureType, 0, 0, 0, width, height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _pixels + 4 * (top * (_DVFrameWidth + 16) + left));

                            glBegin(GL_QUADS);
                                glColor3f(1.0, 1.0, 1.0);
                                
                                glTexCoord2i(MAX(0, _maskLeft - left), 0);
                                glVertex2i(MAX(left, _borderLeft) ,_DVFrameHeight - top);
                                
                                glTexCoord2i(MIN(width, _DVFrameWidth - _maskRight - left), 0);
                                glVertex2i(MIN(left + width, _DVFrameWidth - _borderRight), _DVFrameHeight - top);

                                glTexCoord2i(MIN(width, _DVFrameWidth - _maskRight - left), height);
                                glVertex2i(MIN(left + width, _DVFrameWidth - _borderRight), _DVFrameHeight - top - height);

                                glTexCoord2i(MAX( 0, _maskLeft - left), height);
                                glVertex2i(MAX(left, _borderLeft) ,_DVFrameHeight - top - height);
                            glEnd();
                            textureNumber++;
                            left += width;
                        }
                        top += height;
                    }
                }
                glFinish();
                [[self openGLContext] flushBuffer];
                [_decompLock unlock];
            }
        }
    } else {
        [[self openGLContext] makeCurrentContext];
        glClear(GL_COLOR_BUFFER_BIT);
        glFinish();
        [[self openGLContext] flushBuffer];
    }

    return err;
}

-(BOOL)isOpaque
{
    return YES;
}

-(void)drawRect:(NSRect)rect
{
    if (_decompSeq) 
        [self decompToWindow];
}

- (void)painter:(id)ignore
{
    NSAutoreleasePool *pool;
    void *shmCPF;
    pool = [NSAutoreleasePool new];

NS_DURING
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DBDVViewTimeShare"]) {
        policy_rr_base_data_t rr;
        kern_return_t result;

        rr.base_priority = 0x20;
        rr.quantum = 0;
        result = thread_policy(mach_thread_self(), POLICY_RR, (policy_base_t)&rr, POLICY_RR_BASE_COUNT, true);
    }

    [_painterLock lock];
    _painterThreads++;
    while (_grabber != nil) {
        while (_grabber != nil && ((shmCPF = (void *)_sharedMemory->currentlyPlayingFrame) && ((DBDVFrameInfoPtr)((void *)_sharedMemory + (shmCPF - _sharedMemory->baseAddress)))->timesPainted != 0))
            usleep(1000);

        if ([self lockFocusIfCanDraw]) {
            [self decompToWindow];
            [self unlockFocus];
        } else
            usleep(5000);

        while (shmCPF == NULL && _grabber != nil) {
            usleep(5000);
            shmCPF = (void *)_sharedMemory->currentlyPlayingFrame;
        }
    }
    _painterThreads--;
    [_painterLock unlock];
    [pool release];
    
NS_HANDLER

    _grabber = nil;
    NSLog(@"Exception raised in -[DBDVView painter:] : %@", [localException name]);
    [_painterLock unlock];
    _painterThreads--;
    NSRunCriticalAlertPanel(NSLocalizedString( @"An error has occurred", nil ), [NSString stringWithFormat:NSLocalizedString( @"%@:\n%@\n\nVidi will quit.", nil ), [localException name], [localException description]], NSLocalizedString( @"Quit", nil ), nil, nil);
    [NSApp stop:nil];

NS_ENDHANDLER
}

- (NSImage *)currentImage
{
    [self _updateImage];
    return _dragResizeImage;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    if (_fullScreen)
        [NSApp preventWindowOrdering];
    else {
        NSEvent *nextEvent = [NSApp nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask) untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];
        if ([nextEvent type]==NSLeftMouseDragged) {
            NSSize dragOffset = NSZeroSize;
            NSPoint dragSrcPoint;
            NSPasteboard *pboard;
            NSImage *image = [self currentImage];
            NSImage *thumbnail = [[[NSImage alloc] initWithSize:NSMakeSize(320, 240)] autorelease];

            [thumbnail lockFocus];
                [image drawInRect:NSMakeRect(0, 0, 320, 240) fromRect:NSMakeRect(0, 0, _DVFrameWidth, _DVFrameHeight) operation:NSCompositeCopy fraction:0.5];
            [thumbnail unlockFocus];

            pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
            [pboard declareTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:self];
            [pboard setData:[image TIFFRepresentation] forType:NSTIFFPboardType];

            dragSrcPoint = [self convertPoint:[event locationInWindow] fromView:[[self window] contentView]];
            dragSrcPoint.x -= 160;
            dragSrcPoint.y -= 120;

            [self dragImage:thumbnail at:dragSrcPoint offset:dragOffset event:event pasteboard:pboard source:self slideBack:YES];
        }
    }
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag
{
    return NSDragOperationCopy;
}

@end
