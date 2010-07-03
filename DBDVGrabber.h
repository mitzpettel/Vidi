//
//  DBDVGrabber.h
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 22 2003.
//  Copyright (c) 2003, 2004, 2006, 2007 Mitz Pettel. All rights reserved.
//

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <IOKit/DV/DVFamily.h>


struct DBDVFrameInfo {
    ScheduledSoundHeaderPtr sndHead;
    void *frameBuffer;
    unsigned timesPainted;
    BOOL needsPlaying;
    BOOL needsWriting;
    QElemPtr freeQElem;
    QElemPtr playQElem;
    QElemPtr writeQElem;
};

typedef struct DBDVFrameInfo DBDVFrameInfo;
typedef DBDVFrameInfo *DBDVFrameInfoPtr;

struct DBDVGrabberSharedMemory {
    void *baseAddress;
    DBDVFrameInfo *currentlyPlayingFrame;
    unsigned numUnpainted;
    unsigned char buffer[0];
};

typedef struct DBDVGrabberSharedMemory DBDVGrabberSharedMemory;

struct DBFrameQElem {
  struct QElem *qLink;
  short qType;
  DBDVFrameInfoPtr frameInfo;
};

typedef struct DBFrameQElem DBFrameQElem;
typedef DBFrameQElem *DBFrameQElemPtr;

typedef unsigned long DBTVFrequency;

typedef enum _DBDVInputSource {
    DBTunerInput,
    DBCompositeInput,
    DBSVideoInput,
    DBRadioInput,
    DBUnknownInput
} DBDVInputSource;

typedef enum _DBDVColorSystem {
    DBNTSCSystem = 0,
    DBPALBGSystem = 1,
    DBSECAMSystem = 2
} DBDVColorSystem;

typedef enum _DBDVFormat {
    DBNTSCFormat = 0,
    DBPALFormat = 1,
    DBUnknownFormat
} DBDVFormat;

@protocol DBDVGrabber
- (DBDVFormat)DVFormat;
- (DBDVColorSystem)colorSystem;
- (void)setBrightness:(UInt8)b contrast:(SInt8)c saturation:(SInt8)s hue:(SInt8)h;
- (void)setVolume:(int)volume;
- (int)volume;
- (BOOL)hasTuner;
- (BOOL)hasRadioTuner;
- (unsigned)firmwareVersion;
- (NSString *)tunerDisplayName;
@end

@interface DBDVGrabber : NSObject <DBDVGrabber> {
    NSFileHandle *_fileHandle;
    NSFileHandle *_nextFileHandle;
    ComponentInstance _controlComponent;
    NSDictionary *_tunerInfo;
    unsigned _firmwareVersion;
    // _supposedCurrentFrequency is used for the frequency-switching logic.
    // We have no way of querying the tuner for its real frequency, do we?
    DBTVFrequency _supposedCurrentFrequency;
    UInt8 _brightness;
    SInt8 _contrast;
    SInt8 _saturation;
    SInt8 _hue;
    IONotificationPortRef _notificationPort;
    int _frameSize;
    DVNotificationID _DVNotificationID;
    DVDeviceID _deviceID;
    DVDeviceRefNum _deviceRefNum;
    BOOL _deviceHasAVC;
    SndChannelPtr _soundChannel;
    unsigned long _bytesWrittenToFile;
    unsigned long _chunkSize;
    int _volume;
    SInt16 _DVFormat;
    NSLock *_readerLock;
    NSLock *_writerLock;
    NSLock *_fileLock;
    id _delegate;
    int _sharedMemoryFile;

    int _framesToDrop;

    SoundConverter _soundConverter;
    void *_soundOutputBuffer;
    unsigned long _soundFramesWrittenToFile;
    BOOL _audioOnly;
    UnsignedFixed _audioSampleRate;
    int _audioSampleSize;
    int _audioChannels;
    OSType _audioCompression;
    NSData *_audioCompressionParams;

    io_object_t _powerNotifier;    

@public
    BOOL _isLogging;
    DBDVGrabberSharedMemory *_sharedMemory;	
    BOOL _audioEnabled;
    BOOL _soundStarted;
    BOOL _isGrabbing;
    BOOL _isRecording;
    DBFrameQElemPtr _currentlyPlaying; 
    int _numFullBuffers;
    int _numToBePlayed;
    QHdr _freeForWriting;
    QHdr _toBePlayed;
    QHdr _toBeWritten;
    BOOL _errorSentToMainThread;
    io_connect_t _root_power_port;
}

- (BOOL)getTunerInfo;
- (BOOL)deviceAdded:(DVDeviceID)deviceID;
- (void)deviceRemoved;
- (void)setFile:(NSFileHandle *)file;
- (void)setChunkSize:(unsigned long)size;
- (void)setAudioRecording:(BOOL)flag sampleRate:(UnsignedFixed)rate sampleSize:(int)size channels:(int)chans compression:(OSType)codec parameters:(NSData *)params;
- (void)setDelegate:(id)anObject;
- (id)delegate;
- (void)getBrightness:(UInt8 *)b contrast:(SInt8 *)c saturation:(SInt8 *)s hue:(SInt8 *)h;

- (OSErr)doAVCCommand:(UInt8 *)cmd length:(int)len;
- (OSErr)doAVCCommand:(UInt8 *)cmd length:(int)len response:(UInt8 *)rsp size:(int *)bufflen;
- (void)doPictureSettingsCommand;

- (void)setAudioSamplingRate;
- (BOOL)startGrabbing;
- (void)stopGrabbing;
- (BOOL)isGrabbing;
- (BOOL)hasDevice;
- (BOOL)canStartGrabbing;
- (void)setInputSource:(DBDVInputSource)source;
- (DBDVInputSource)inputSource;
- (void)setFrequency:(DBTVFrequency)freq;
- (void)setRadioFrequency:(DBTVFrequency)freq;
- (void)startRecording;
- (void)stopRecording;
- (BOOL)isRecording;

- (void)dropNextFrames:(int)frames;

- (BOOL)isAudioEnabled;
- (void)setAudioEnabled:(BOOL)flag;

- (unsigned)bufferCount;

@end

@interface NSObject (DBDVGrabberDelegate)

- (void)grabberDidAcquireDevice:(DBDVGrabber *)grabber;
- (void)grabberDidLoseDevice:(DBDVGrabber *)grabber;
- (void)grabberDidStartRecording:(DBDVGrabber *)grabber;
- (void)grabberDidStopRecording:(DBDVGrabber *)grabber;
- (void)grabberDidStartGrabbing:(DBDVGrabber *)grabber;
- (void)grabberDidStopGrabbing:(DBDVGrabber *)grabber;
- (NSFileHandle *)grabberNeedsNextFileHandle;
- (void)grabberHadErrorWriting:(DBDVGrabber *)grabber;

@end
