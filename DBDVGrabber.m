//
//  DBDVGrabber.m
//  Vidi
//
//  Created by Mitz Pettel on Wed Jan 22 2003.
//  Copyright (c) 2003, 2004, 2005, 2006, 2007 Mitz Pettel. All rights reserved.
//


#import "DBDVGrabber.h"

#import <IOKit/IOMessage.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <QuickTime/QuickTimeComponents.h>
#import "audio.h"
#import <fcntl.h>
#import <mach/mach.h>
#import <sys/ipc.h>
#import <sys/mman.h>
#import <sys/shm.h>
#import <sys/types.h>
#import <unistd.h>

void MKGetTimeBaseInfo(unsigned *delta, unsigned *abs_to_ns_num, unsigned *abs_to_ns_denom, unsigned *proc_to_abs_num, unsigned *proc_to_abs_denom);

@interface DBDVGrabber (DBDVGrabberPrivate)
- (void)setupAndBeginSoundConversionFor:(void *)DVFrame;
@end

static pascal void soundCallback (SndChannelPtr theChannel, SndCommand * theCallBackCmd);

static OSStatus myDVNotifyProc(DVEventRecordPtr event, void *userData )
{
    DBDVGrabber		*grabber = userData;
    if (event->eventHeader.theEvent == kDVDeviceAdded)
    {
        NSAutoreleasePool	*pool;
        pool = [NSAutoreleasePool new];
        [grabber deviceAdded:event->eventHeader.deviceID];
        [pool release];
    }
    return noErr;
}

typedef struct DVFuncsStruct {
    UInt32 (*fDVCountDevices)(void);
    OSErr (*fDVGetIndDevice)(DVDeviceID * pDVDevice, UInt32 index);
    OSErr (*fDVSetDeviceName)(DVDeviceID deviceID, char * str);
    OSErr (*fDVGetDeviceName)(DVDeviceID deviceID, char * str);

    OSErr (*fDVOpenDriver)(DVDeviceID deviceID, DVDeviceRefNum *pRefNum);
    OSErr (*fDVCloseDriver)(DVDeviceRefNum refNum);

    OSErr (*fDVDoAVCTransaction)(DVDeviceRefNum refNum, AVCTransactionParamsPtr pParams);

    OSErr (*fDVIsEnabled)(DVDeviceRefNum refNum, Boolean *isEnabled);
    OSErr (*fDVGetDeviceStandard)(DVDeviceRefNum refNum, UInt32 * pStandard);

    // DV Isoch Read
    OSErr (*fDVEnableRead)(DVDeviceRefNum refNum);
    OSErr (*fDVDisableRead)(DVDeviceRefNum refNum);
    OSErr (*fDVReadFrame)(DVDeviceRefNum refNum, Ptr *ppReadBuffer, UInt32 * pSize);
    OSErr (*fDVReleaseFrame)(DVDeviceRefNum refNum, Ptr pReadBuffer);

    // DV Isoch Write
    OSErr (*fDVEnableWrite)(DVDeviceRefNum refNum);
    OSErr (*fDVDisableWrite)(DVDeviceRefNum refNum);
    OSErr (*fDVGetEmptyFrame)(DVDeviceRefNum refNum, Ptr *ppEmptyFrameBuffer, UInt32 * pSize);
    OSErr (*fDVWriteFrame)(DVDeviceRefNum refNum, Ptr pWriteBuffer);
    OSErr (*fDVSetWriteSignalMode)(DVDeviceRefNum refNum, UInt8 mode);
    
    // Notifications
    OSErr (*fDVNewNotification)(DVDeviceRefNum refNum, DVNotifyProc notifyProc, void *userData, DVNotificationID *pNotifyID);	
    OSErr (*fDVNotifyMeWhen)(DVDeviceRefNum refNum, DVNotificationID notifyID, UInt32 events);
    OSErr (*fDVCancelNotification)(DVDeviceRefNum refNum, DVNotificationID notifyID);
    OSErr (*fDVDisposeNotification)(DVDeviceRefNum refNum, DVNotificationID notifyID);

} DVFuncs, *DVFuncsPtr;

static DVFuncs sDVFuncs;

void powerCallback(void *refcon, io_service_t y, natural_t messageType, void *messageArgument)
{
    DBDVGrabber *grabber = refcon;
    OSErr err = noErr;
    int nDevices;
    int i;
    DVDeviceID deviceID;

    if ( grabber->_isLogging )
        NSLog(@"DBDVGrabber powerCallback message type: 0x%x", messageType);

    switch (messageType) {
        case kIOMessageCanSystemSleep:
        case kIOMessageCanSystemPowerOff:
            if ([grabber isRecording])
                IOCancelPowerChange(grabber->_root_power_port, (long)messageArgument);
            else
                IOAllowPowerChange(grabber->_root_power_port, (long)messageArgument);
            break;
        case kIOMessageSystemWillSleep:
        case kIOMessageSystemWillPowerOff:
            [grabber deviceRemoved];
            IOAllowPowerChange(grabber->_root_power_port, (long)messageArgument);
            break;
        case kIOMessageSystemHasPoweredOn:
            IOAllowPowerChange(grabber->_root_power_port, (long)messageArgument);
            nDevices = sDVFuncs.fDVCountDevices();
            for (i = 0; i<nDevices; i++) {
                err = sDVFuncs.fDVGetIndDevice(&deviceID, i+1);
                [grabber deviceAdded:deviceID];
            }
            break;
        default:
            IOAllowPowerChange(grabber->_root_power_port, (long)messageArgument);
            break;
    }
}

static void disableRobustAVCResponseMatching()
{
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(dict) {
        CFDictionarySetValue(dict, CFSTR("RobustAVCResponseMatching"), CFSTR("False"));

        CFMutableDictionaryRef matching = IOServiceMatching("IOFireWireAVCUnit");
        io_iterator_t iterator;
        kern_return_t ret = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator);
        if (ret == kIOReturnSuccess) {
            io_service_t service;
            while (service = IOIteratorNext(iterator))
                IORegistryEntrySetCFProperties(service, dict);

            IOObjectRelease(iterator);
        }
        CFRelease(dict);
    }
}

NSString * const DBVidiTunerOverrideSettingName = @"tunerOverride";
NSString * const DBVidiFirmwareOverrideSettingName = @"firmwareOverride";
NSString * const DBVidiDisableRobustAVCResponseMatchingSettingName = @"disableRobustAVCResponseMatching";

NSString * const DBDVDisallowedOperationException = @"DBDVDisallowedOperationException";
NSString * const DBDVErrorException = @"DBDVErrorException";
NSString * const DBDVIllegalParameterException = @"DBDVIllegalParameterException";
NSString * const DBDVUnknownTunerException = @"DBDVUnknownTunerException";

NSString * const DBTunerRadioKey = @"radio";
NSString * const DBTunerDisplayNameKey = @"name";
NSString * const DBTunerBandsKey = @"bands";
NSString * const DBTunerMaxFrequencyKey = @"max freq";
NSString * const DBTunerOpcodeKey = @"opcode";

@implementation DBDVGrabber

+ (void)initialize
{
    CFBundleRef myBundle;
    BOOL didLoad;

    myBundle = CFBundleCreate(nil, (CFURLRef)[NSURL URLWithString:@"/System/Library/Extensions/DVFamily.bundle"]);
    if (!myBundle)
        goto error;
    // Try to load the executable from my bundle.
    didLoad = CFBundleLoadExecutable(myBundle);
    if (!didLoad)
        goto error;

    sDVFuncs.fDVCountDevices = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVCountDevices"));
    sDVFuncs.fDVGetIndDevice = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVGetIndDevice"));
    sDVFuncs.fDVSetDeviceName = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVSetDeviceName"));
    sDVFuncs.fDVGetDeviceName = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVGetDeviceName"));
    sDVFuncs.fDVOpenDriver = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVOpenDriver"));
    sDVFuncs.fDVCloseDriver = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVCloseDriver"));
    sDVFuncs.fDVDoAVCTransaction = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVDoAVCTransaction"));
    sDVFuncs.fDVIsEnabled = CFBundleGetFunctionPointerForName(myBundle,CFSTR("DVIsEnabled"));
    sDVFuncs.fDVGetDeviceStandard = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVGetDeviceStandard"));
    sDVFuncs.fDVEnableRead = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVEnableRead"));
    sDVFuncs.fDVDisableRead = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVDisableRead"));
    sDVFuncs.fDVReadFrame = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVReadFrame"));
    sDVFuncs.fDVReleaseFrame = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVReleaseFrame"));
    sDVFuncs.fDVEnableWrite = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVEnableWrite"));
    sDVFuncs.fDVDisableWrite = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVDisableWrite"));
    sDVFuncs.fDVGetEmptyFrame = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVGetEmptyFrame"));
    sDVFuncs.fDVWriteFrame = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVWriteFrame"));
    sDVFuncs.fDVSetWriteSignalMode = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVSetWriteSignalMode"));
    sDVFuncs.fDVNewNotification = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVNewNotification"));
    sDVFuncs.fDVNotifyMeWhen = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVNotifyMeWhen"));
    sDVFuncs.fDVCancelNotification = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVCancelNotification"));
    sDVFuncs.fDVDisposeNotification = CFBundleGetFunctionPointerForName(myBundle, CFSTR("DVDisposeNotification"));
    return;

error:
    [NSException raise:DBDVErrorException format:@"+[DBDVGrabber intialize] couldn't load DVFamily.bundle"];
}

- (id)init
{
    OSErr err = noErr;
    int nDevices;
    int i;
    DVDeviceID deviceID;
    IONotificationPortRef notificationPort;

    self = [super init];

    if (self) {
        _isGrabbing = NO;
        _fileHandle = NULL;
        _nextFileHandle = NULL;
        _volume = 255;
        _readerLock = [NSLock new];
        _writerLock = [NSLock new];
        _fileLock = [NSLock new];
        _isLogging = [[NSUserDefaults standardUserDefaults] boolForKey:@"DBVidiLog"];

        nDevices = sDVFuncs.fDVCountDevices();	// initializes DVFamily

        err = sDVFuncs.fDVNewNotification(kEveryDVDeviceID, myDVNotifyProc, self, &_DVNotificationID);
        if (err)
            goto error;

        err = sDVFuncs.fDVNotifyMeWhen(kEveryDVDeviceID, _DVNotificationID, kDVEveryEvent);
        if (err)
            goto error;

        for (i = 0; i < nDevices; i++) {
            err = sDVFuncs.fDVGetIndDevice(&deviceID, i + 1);
            [self deviceAdded:deviceID];
        }

        err = SndNewChannel(&(_soundChannel), sampledSynth, 0, NewSndCallBackUPP(soundCallback));
        if (err)
            goto error;

        _root_power_port = IORegisterForSystemPower(self, &notificationPort, powerCallback, &_powerNotifier);
        if (!_root_power_port) {
            err = 1;
            goto error;
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
    }
        
error:
    if (err != noErr)
        [NSException raise:DBDVErrorException format:@"-[DBDVGrabber init] encountered error %d(0x%x).", err, err];

    return self;
}

- (void)readerRanOutOfBuffers:(id)ignore
{
    // FIXME: Do something when this happens.
}

- (void)writerGotError:(id)ignore
{
    if ([_delegate respondsToSelector:@selector(grabberHadErrorWriting:)])
        [_delegate grabberHadErrorWriting:self];
    _errorSentToMainThread = NO;
}

- (void)writerSwappedFile:(id)ignore
{
    NSFileHandle *next = nil;

    if ([_delegate respondsToSelector:@selector(grabberNeedsNextFileHandle)])
        next = [_delegate grabberNeedsNextFileHandle];

    [_fileLock lock];
        [_nextFileHandle autorelease];
        if (next)
            _nextFileHandle = [next retain];
        else
            _nextFileHandle = [_fileHandle retain];
    [_fileLock unlock];
}

- (void)dealloc
{
    if ([self isGrabbing])
        [self stopGrabbing];
    if (_root_power_port)
        IODeregisterForSystemPower(&_powerNotifier);
    sDVFuncs.fDVCancelNotification(kEveryDVDeviceID, _DVNotificationID);
    sDVFuncs.fDVDisposeNotification(kEveryDVDeviceID, _DVNotificationID);
    if (_deviceID != kInvalidDVDeviceID)
        [self deviceRemoved];
    if (_soundChannel)
        SndDisposeChannel(_soundChannel, true);
    [_tunerInfo release];
    [_audioCompressionParams release];
    [_readerLock release];
    [_writerLock release];
    [_fileLock release];
    [super dealloc];
}

- (void)setDelegate:(id)anObject
{
    _delegate = anObject;
}

- (id)delegate
{
    return _delegate;
}

- (BOOL)isGrabbing
{
    return _isGrabbing;
}

- (OSErr)doAVCCommand:(UInt8 *)cmd length:(int)len;
{
    UInt8 rsp[8];
    int size = 8;
    return [self doAVCCommand:cmd length:len response:rsp size:&size];
}

- (OSErr)doAVCCommand:(UInt8 *)cmd length:(int)len response:(UInt8 *)rsp size:(int *)bufflen;
{
    IOReturn err;
    AVCTransactionParams params;
    params.commandBufferPtr = (char *)cmd;
    params.commandLength = len;
    params.responseBufferPtr = (char *)rsp;
    params.responseBufferSize = *bufflen;
    params.responseHandler = nil;

retry:
    if (_isLogging)
        NSLog(@" Command (length %d)>> %02x %02x %02x %02x : %02x %02x %02x %02x", params.commandLength, cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7]);

    err = sDVFuncs.fDVDoAVCTransaction(_deviceRefNum, &params);

    *bufflen = params.responseBufferSize;
    if ( _isLogging ) {
        NSLog(@"Response (length %d)<< %02x %02x %02x %02x : %02x %02x %02x %02x", params.responseBufferSize, rsp[0], rsp[1], rsp[2], rsp[3], rsp[4], rsp[5], rsp[6], rsp[7]);
        NSLog(@"Error                  %d", err);
    }

    if (err == err_get_code(kIOReturnTimeout) && ![[NSUserDefaults standardUserDefaults] boolForKey:DBVidiDisableRobustAVCResponseMatchingSettingName]) {
        if (_isLogging)
            NSLog(@"Disabling robust AVC response matching and retrying.");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:DBVidiDisableRobustAVCResponseMatchingSettingName];
        disableRobustAVCResponseMatching();
        goto retry;
    }

    return err;
}

- (BOOL)hasDevice
{
    OSErr err;
    UInt8 cmd[8] = {0x02, 0xff, 0x30, 0xff, 0xff, 0xff, 0xff, 0xff };	// specific inquiry to the unit
    
    if (_deviceID!=kInvalidDVDeviceID && _deviceHasAVC) {
        err = [self doAVCCommand:cmd length:8];
        if (err == 3)
            [self deviceRemoved];
        else if (err)
            _deviceHasAVC = NO;
    }

    if (_isLogging)
        NSLog(@"-[DBDVGrabber hasDevice] : %d", (_deviceID != kInvalidDVDeviceID));

    return (_deviceID != kInvalidDVDeviceID);
}

- (BOOL)hasRadioTuner
{
    return [_tunerInfo objectForKey:DBTunerRadioKey] != nil;
}

- (BOOL)canStartGrabbing
{
    OSErr err;
    
    if (![self hasDevice])
        return NO;
    if ([self isGrabbing])
        return YES;
    err = sDVFuncs.fDVEnableRead(_deviceRefNum);
    if (err)
        return NO;
    sDVFuncs.fDVDisableRead(_deviceRefNum);
    return YES;
}

- (void)setAudioSamplingRate
{
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DBVidiSendAudioCommand"])
        return;

    if ([self firmwareVersion] > 0x01000500 && [self firmwareVersion] < 0x02000000) {
        UInt8 cmd[4] = { 0x02, 0xab, 0x31, 0xc0 };
        UInt8 rsp[4];
        int size;
        
        // 32KHz audio on 1.0.7 firmware. First ask if it's supported
        size = 4;
        [self doAVCCommand:cmd length:4 response:rsp size:&size];
        // If it is, go ahead and do it
        if (rsp[0] == 0x0c) {
            // Get the current audio mode
            cmd[0] = 0x01;
            cmd[3] = 0x00;
            [self doAVCCommand:cmd length:4 response:rsp size:&size];
            // FIXME: Perhaps this needs to be done only if rsp[3] != 0xc0, i.e. if not 32KHz
            cmd[0] = 0x00;
            cmd[3] = 0xc0;
            [self doAVCCommand:cmd length:4];	// change to 32KHz
            cmd[2] = 0x19;
            cmd[3] = 0x02;
            [self doAVCCommand:cmd length:4];	// a reset to activate it
            usleep( 200000 );		// wait for reset to complete
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DBVidiPostAudioWait"])
                usleep(800000);
        }
    }
}

- (void)dropNextFrames:(int)frames
{
    _framesToDrop = frames;
}

- (BOOL)startGrabbing
{
    OSErr err = noErr;

    if (!_isGrabbing) {
        UInt8 cmd[4] = { 0x00, 0xab, 0x14, 0x01 }; // A->D mode

        err = sDVFuncs.fDVEnableRead(_deviceRefNum);
        if (err)
            return NO;

        if (_firmwareVersion != 0)
            [self doAVCCommand:cmd length:4];
        else {
            cmd[1] = 0x20;  // subunit type 4 (VTR), ID 0
            cmd[2] = 0xc3;  // play opcode
            cmd[3] = 0x7d;  // pause operand
            [self doAVCCommand:cmd length:4];
        }

        [self setAudioSamplingRate];
        [self doPictureSettingsCommand];

        _isGrabbing = YES;
        [NSThread detachNewThreadSelector:@selector(writer:) toTarget:self withObject:nil];
        [NSThread detachNewThreadSelector:@selector(reader:) toTarget:self withObject:nil];    
        if (_delegate && [_delegate respondsToSelector:@selector(grabberDidStartGrabbing:)])
            [_delegate grabberDidStartGrabbing:self];
    } else
        [NSException raise:DBDVDisallowedOperationException format:@"-[DBDVGrabber startGrabbing] received while grabbing."];

    return YES;
}

- (void)stopGrabbing
{
    DBFrameQElemPtr frameQElem;
    if (_isGrabbing) {
        if (_isRecording)
            [self stopRecording];
        _isGrabbing = NO;
        [_readerLock lock];
        [_readerLock unlock];
        [_writerLock lock];
        [_writerLock unlock];

        while (frameQElem = (DBFrameQElemPtr)(_toBePlayed.qHead)) {
            Dequeue((QElemPtr)frameQElem, &(_toBePlayed));
            _numToBePlayed--;
        }

        while (frameQElem = (DBFrameQElemPtr)(_toBeWritten.qHead)) {
            Dequeue((QElemPtr)frameQElem, &(_toBeWritten));
            Enqueue(frameQElem->frameInfo->freeQElem, &(_freeForWriting));
            _numFullBuffers--;
        }

        sDVFuncs.fDVDisableRead(_deviceRefNum);

        if (_delegate && [_delegate respondsToSelector:@selector(grabberDidStopGrabbing:)])
            [_delegate grabberDidStopGrabbing:self];
    }
    else
        [NSException raise:DBDVDisallowedOperationException format:@"-[DBDVGrabber stopGrabbing] received while not grabbing."];
}

- (void)writer:(id)ignore
{
    DBFrameQElemPtr frameQElem;
    int fd;
    NSFileHandle *oldFileHandle;	// don't want an autorelease pool here
    ssize_t bytesWritten;
    unsigned long soundOutputFrames;
    unsigned long soundOutputBytes;
    
    [_writerLock lock];
    if (_isLogging)
        NSLog(@"_writeLock locked");

    while (_isGrabbing) {
        frameQElem = (DBFrameQElemPtr)(_toBeWritten.qHead);
        // process the _toBeWritten queue
        while (frameQElem)
        {
            // first of all, write the frame if necessary
            if (frameQElem->frameInfo->needsWriting) {
                [_fileLock lock];
                if ((fd = [_fileHandle fileDescriptor]) && !_errorSentToMainThread) {
                    if (_audioOnly) {
                        if (_soundConverter == NULL)
                            [self setupAndBeginSoundConversionFor:frameQElem->frameInfo->frameBuffer];
                        SoundConverterConvertBuffer(_soundConverter, frameQElem->frameInfo->frameBuffer, 1, _soundOutputBuffer, &soundOutputFrames, &soundOutputBytes);                               
                        bytesWritten = write(fd, _soundOutputBuffer, soundOutputBytes);
                        _soundFramesWrittenToFile += soundOutputFrames;
                    } else
                        bytesWritten = write(fd, frameQElem->frameInfo->frameBuffer, _frameSize);

                    if (bytesWritten == -1) {
                        _errorSentToMainThread = YES;
                        [self performSelectorOnMainThread:@selector(writerGotError:) withObject:nil waitUntilDone:NO];
                    } else {
                        _bytesWrittenToFile += bytesWritten;
                        if (_chunkSize != 0 && _chunkSize < _bytesWrittenToFile + _frameSize) {
                            oldFileHandle = _fileHandle;
                            _fileHandle = [_nextFileHandle retain];
                            [oldFileHandle release];
                            _bytesWrittenToFile = 0;
                            [self performSelectorOnMainThread:@selector(writerSwappedFile:) withObject:nil waitUntilDone:NO];
                        }
                    }
                }
                [_fileLock unlock];
                // and make sure we don't do it again
                frameQElem->frameInfo->needsWriting = NO;
            }

            // now what do we do with it?
            if (frameQElem->frameInfo->needsPlaying)
                // we can't remove it because it hasn't been played yet, so we just move on
                frameQElem = (DBFrameQElemPtr)frameQElem->qLink;
            else {
                // it's ok to reuse it
                Dequeue((QElemPtr)frameQElem, &(_toBeWritten));
                Enqueue(frameQElem->frameInfo->freeQElem, &(_freeForWriting));
                _numFullBuffers--;
                frameQElem = (DBFrameQElemPtr)(_toBeWritten.qHead);
            }
        }
        usleep(40000);
    }

    [_writerLock unlock];
    if (_isLogging)
        NSLog(@"_writeLock unlocked");
}

- (void)setChunkSize:(unsigned long)size
{
    _chunkSize = size;
}

- (void)setAudioRecording:(BOOL)flag sampleRate:(UnsignedFixed)rate sampleSize:(int)size channels:(int)chans compression:(OSType)codec parameters:(NSData *)params
{
    if (![self isRecording]) {
        _audioOnly = flag;
        if (_audioOnly) {
            _audioSampleRate = rate;
            _audioSampleSize = size;
            _audioChannels = chans;
            _audioCompression = codec;
            [_audioCompressionParams autorelease];
            _audioCompressionParams = [params retain];
        } else {
            [_audioCompressionParams release];
            _audioCompressionParams = nil;
        }
    } else
        [NSException raise:DBDVDisallowedOperationException format:@"-[DBDVGrabber setAudioRecording:sampleRate:sampleSize:channels:compression:] received during recording."];
}

- (void)setFile:(NSFileHandle *)file
{
    if (![self isRecording]) {
        [_fileLock lock];
        [_fileHandle autorelease];
        [_nextFileHandle autorelease];
        _fileHandle = [file retain];
        _nextFileHandle = nil;
        [_fileLock unlock];
    } else
        [NSException raise:DBDVDisallowedOperationException format:@"-[DBDVGrabber setFile:] received during recording."];
}

- (void)writeAIFFHeaderToFileHandle:(NSFileHandle *)file
{
    int fd = [file fileDescriptor];
    double fracSampleRate = ((double)_audioSampleRate) / 65536.0;
    ContainerChunk container = { FORMID, 0, AIFCID };
    FormatVersionChunk version = { FormatVersionID, sizeof(FormatVersionChunk) - 8, AIFCVersion1 };
    ExtCommonChunk common = { CommonID, sizeof(ExtCommonChunk) - 8, _audioChannels, _soundFramesWrittenToFile, _audioSampleSize, { 0, {0, 0, 0, 0 } }, _audioCompression };
    ChunkHeader params = { siDecompressionParams, 0 };
    SoundDataChunk data = { SoundDataID, _bytesWrittenToFile - 8 + sizeof(SoundDataChunk), 0, 0 };

    dtox80(&fracSampleRate, &common.sampleRate);

    container.ckSize = _bytesWrittenToFile + sizeof(ContainerChunk) + sizeof(ExtCommonChunk) + sizeof(SoundDataChunk);

    if (_audioCompressionParams)
        container.ckSize += sizeof(params) + [_audioCompressionParams length];

    write(fd, &container, sizeof(container));
    write(fd, &version, sizeof(version));
    write(fd, &common, sizeof(common));
    if (_audioCompressionParams) {
        params.ckSize = [_audioCompressionParams length];
        write(fd, &params, sizeof(params));
        write(fd, [_audioCompressionParams bytes], params.ckSize);
    }
    write(fd, &data, sizeof(data));
}

- (void)setupAndBeginSoundConversionFor:(void *)DVFrame
{
    SoundComponentData input = {
        0,			// flags
        kDVAudioFormat,		// format
        2,			// numChannels
        16,			// sampleSize
        0,			// sampleRate
        0,			// sampleCount
        0,			// buffer
        0			// reserved
    };

    SoundComponentData output = {
        0,			// flags
        _audioCompression,	// format
        _audioChannels,		// numChannels
        _audioSampleSize,	// sampleSize
        _audioSampleRate,	// sampleRate
        0,			// sampleCount
        0,			// buffer
        0			// reserved
    };

    unsigned char audioType =  *((unsigned char *)DVFrame+4327) & 0x38;

    switch (audioType) {
        case 0x00:	// 48.0kHz
            input.sampleRate = rate48khz;
            break;
        case 0x08:	// 44.1kHz
            input.sampleRate = rate44khz;
            break;
        case 0x10:	// 32.0kHz
            input.sampleRate = rate32khz;
            break;
        default:
            break;
    }

    SoundConverterOpen(&input, &output, &_soundConverter);

    if (_audioCompressionParams)
        SoundConverterSetInfo(_soundConverter, siCompressionParams, (void *)[_audioCompressionParams bytes]);

    _soundOutputBuffer = malloc(10240); // FIXME

    SoundConverterBeginConversion(_soundConverter);
    [self writeAIFFHeaderToFileHandle:_fileHandle];
}

- (void)startRecording
{
    if (_fileHandle && !_isRecording) {
        _bytesWrittenToFile = 0;
        _soundFramesWrittenToFile = 0;
        if (_chunkSize != 0)
            [self writerSwappedFile:nil];        
        _isRecording = YES;
        if (_delegate && [_delegate respondsToSelector:@selector(grabberDidStartRecording:)])
            [_delegate grabberDidStartRecording:self];
    } else
        [NSException raise:DBDVDisallowedOperationException format:@"-[DBDVGrabber startRecording] received while the destination file was unspecified."];
}

- (void)stopRecording
{
    NSFileHandle *finishedFile;
    unsigned long soundOutputFrames;
    unsigned long soundOutputBytes;

    if (_isRecording) {
        _isRecording = NO;
        finishedFile  = [_fileHandle retain];
        [self setFile:nil];
        if (_audioOnly && _soundConverter != NULL) {
            SoundConverterEndConversion(_soundConverter, _soundOutputBuffer, &soundOutputFrames, &soundOutputBytes);
            write([finishedFile fileDescriptor], &_soundOutputBuffer, soundOutputBytes);
            _bytesWrittenToFile += soundOutputBytes;
            _soundFramesWrittenToFile += soundOutputFrames;
            SoundConverterClose(_soundConverter);
            _soundConverter = nil;
            free(_soundOutputBuffer);
            lseek([finishedFile fileDescriptor], 0, SEEK_SET);
            [self writeAIFFHeaderToFileHandle:finishedFile];
        }
        [finishedFile release];
        if (_delegate && [_delegate respondsToSelector:@selector(grabberDidStopRecording:)])
            [_delegate grabberDidStopRecording:self];
    }
}

- (BOOL)isRecording
{
    return _isRecording;
}

- (void)getBrightness:(UInt8 *)b contrast:(SInt8 *)c saturation:(SInt8 *)s hue:(SInt8 *)h
{
    if ([self firmwareVersion] != 0) {
        UInt8 cmd[4] = { 0x01, 0xab, 0x0b, 0x00 };
        UInt8 rsp[8];
        int rspSize = 8;
        [self doAVCCommand:cmd length:4 response:rsp size:&rspSize];
        *b = (UInt8)rsp[rspSize-4];
        *c = (SInt8)rsp[rspSize-3];
        *s = (SInt8)rsp[rspSize-2];
        *h = (SInt8)rsp[rspSize-1];
    }
}

- (void)doPictureSettingsCommand
{
    if ([self firmwareVersion] != 0) {
        UInt8 cmd[8] = {
            0x00,
            0xab,
            0x1a,
            0x00,
            _brightness,
            _contrast,
            _saturation,
            (_DVFormat == ntscIn ? _hue : 0)
        };
        [self doAVCCommand:cmd length:8];
    }
}

- (void)setBrightness:(UInt8)b contrast:(SInt8)c saturation:(SInt8)s hue:(SInt8)h
{
    _brightness = b;
    _contrast = c;
    _saturation = s;
    _hue = h;
    [self doPictureSettingsCommand];
}

- (void)setInputSource:(DBDVInputSource)source
{
    if ([self firmwareVersion] != 0) {
        UInt8 studioSource = 0;
        UInt8 cmd[8] = { 0x00, 0xab };
        // second and third commands needed when switching firmware 2.1.1 and higher to TV tuner
        UInt8 secondCmd[8] = { 0x00, 0xab, 0x01, 0x36, 0x00, 0x00, 0x00, 0x00 };
        UInt8 thirdCmd[12] = { 0x00, 0xab, 0x0c, 0x36, 0x03, 0xc0, 0x00, 0x86, 0xa0, 0x00, 0x24, 0x08 };
        switch (source) {
            case DBTunerInput:
                studioSource = 6;
                break;
            case DBCompositeInput:
                studioSource = 0;
                break;
            case DBSVideoInput:
                studioSource = 1;
                break;
            case DBRadioInput:
                studioSource = 0xee;
                break;
            default:
                [NSException raise:DBDVIllegalParameterException format:@"-[DBDVGrabber setInputSource:] specified illegal source."];
        }
        if (source == DBRadioInput) {
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"reset for radio"]) {
                cmd[2] = 0x13;
                cmd[3] = 0xef;
                [self doAVCCommand:cmd length:4];
                usleep(200000);

                cmd[2] = 0x13;
                cmd[3] = 0x06;
                [self doAVCCommand:cmd length:4];
                usleep(200000);

                cmd[2] = 0x13;
                cmd[3] = 0xef;
                [self doAVCCommand:cmd length:4];
                usleep(200000);

                cmd[2] = 0x13;
                cmd[3] = 0xee;
                [self doAVCCommand:cmd length:4];
                usleep( 200000 );

                cmd[2] = 0x01;
                cmd[3] = 0x03;	// switch tuner off
                cmd[4] = 0x8e;
                cmd[5] = 0xa1;
                [self doAVCCommand:cmd length:8];
                usleep(200000);
            } else {
                UInt8 b;
                SInt8 c;
                SInt8 s;
                SInt8 h;
                [self getBrightness:&b contrast:&c saturation:&s hue:&h];
                cmd[2] = 0x19;
                cmd[3] = 0x01;	// reset
                [self doAVCCommand:cmd length:4];
                usleep(1000000);		// wait for reset to complete

                [self setBrightness:b contrast:c saturation:s hue:h];
                cmd[2] = 0x14;
                cmd[3] = 0x01;
                [self doAVCCommand:cmd length:4];
                cmd[2] = 0x01;
                cmd[3] = 0x03;	// power tuner down
                cmd[4] = 0x8e;
                cmd[5] = 0xa1;
                [self doAVCCommand:cmd length:8];
                usleep(500000);		// wait some more
            }
        }
        cmd[2] = 0x13;
        cmd[3] = studioSource;
        [self doAVCCommand:cmd length:4];
        if ([self firmwareVersion] >= 0x02010100) {
            [self doAVCCommand:secondCmd length:8];
            [self doAVCCommand:thirdCmd length:12];
        }
        if (source == DBRadioInput)
            usleep(200000);
    }
}

- (DBDVFormat)DVFormat
{
    if (_DVFormat == ntscIn)
        return DBNTSCFormat;
    if (_DVFormat == palIn)
        return DBPALFormat;
    return DBUnknownFormat;
}

- (DBDVColorSystem)colorSystem
{
    DBDVColorSystem system;
    UInt8 cmd[4] = { 0x01, 0xab, 0x03, 0x00 };
    UInt8 rsp[4];
    int rspSize = 4;
    [self doAVCCommand:cmd length:4 response:rsp size:&rspSize];
    system = rsp[3];
    return system;
}

- (DBDVInputSource)inputSource
{
    DBDVInputSource source;
    
    if ([self firmwareVersion] != 0)
    {
        UInt8 cmd[4] = { 0x01, 0xab, 0x05, 0x00 };
        UInt8 rsp[4];
        int rspSize = 4;

        [self doAVCCommand:cmd length:4 response:rsp size:&rspSize];
        switch (rsp[3]) {
            case 6:
                source = DBTunerInput;
                break;
            case 0:
                source = DBCompositeInput;
                break;
            case 1:
                source = DBSVideoInput;
                break;
            case 0xee:
                source = DBRadioInput;
                break;
            default:
                source = DBUnknownInput;
                break;
        }
    } else
        source = DBUnknownInput;

    return source;
}

- (BOOL)getTunerInfo
{
    int tunerID;
    UInt8 cmd[4] = { 0x01, 0xab, 0x07, 0x00 };
    UInt8 firmwareCmd[4] = { 0x01, 0xab, 0x02, 0x00};
    UInt8 rsp[24];
    int rspSize = 16;
    
    if (![[NSUserDefaults standardUserDefaults] objectForKey:DBVidiTunerOverrideSettingName]) {
        if (0 == [self doAVCCommand:cmd length:4 response:rsp size:&rspSize])
            tunerID = EndianU16_BtoN(*(UInt16 *)(rsp + rspSize - 2));
        else
            tunerID = 0;
    } else
        tunerID = [[NSUserDefaults standardUserDefaults] integerForKey:DBVidiTunerOverrideSettingName];
    if (_tunerInfo)
        [_tunerInfo release];
    _tunerInfo = [[[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"tuners" ofType:@"plist"]] objectForKey:[[NSNumber numberWithInt:tunerID] stringValue]] retain];
    if (tunerID != 0 && _tunerInfo == nil)
        NSLog(@"Unrecognized tuner model, ID %d.", tunerID);
    
    if (![[NSUserDefaults standardUserDefaults] objectForKey:DBVidiFirmwareOverrideSettingName]) {
        rspSize = 24;
        [self doAVCCommand:firmwareCmd length:4 response:rsp size:&rspSize];
        if (EndianU32_BtoN(((unsigned *)rsp)[0]) == 'PrTV')
            _firmwareVersion = EndianU32_BtoN(((unsigned *)rsp)[1]);
        else if (EndianU32_BtoN(((unsigned *)rsp)[1])=='PrTV')
            _firmwareVersion = EndianU32_BtoN(((unsigned *)rsp)[2]);
    } else
        _firmwareVersion = [[[NSUserDefaults standardUserDefaults] objectForKey:DBVidiFirmwareOverrideSettingName] unsignedIntValue];

    return _tunerInfo != nil;
}

- (NSString *)tunerDisplayName
{
    return [_tunerInfo objectForKey:DBTunerDisplayNameKey];
}

- (BOOL)hasTuner
{
    return _tunerInfo != nil;
}

- (unsigned)firmwareVersion
{
    return _firmwareVersion;
}

- (void)setFrequency:(DBTVFrequency)freq
{
    if ([self hasTuner]) {
        NSArray *bands = [_tunerInfo objectForKey:DBTunerBandsKey];
        int bandsCount = [bands count];
        NSDictionary *band;
        int i;
        // for firmware >= 2.1.1, we fill in positions 5-8 with the I2C commands (freq, band)
        // or (band, freq); for older firmware, we send two 8-byte AVC commands with the I2C command
        // occupying positions 4-5 in each, and zeros in positions 6-7
        UInt8 cmd[12] = { 0x00, 0xab, 0x0c, 0xa1, 0x05, 0, 0, 0, 0, 0xa0, 0x00, 0xa0 };
        // for firmware >= 2.1.1, we send this before the I2C commands (see
        // StudioDevice::SetSmTunerIF in the tuner.codec disassembly)
        UInt8 IFcmd[12] = { 0x00, 0xab, 0x0c, 0x07, 0x04, 0x00, 0x16, 0x50, 0x49, 0x00, 0xa5, 0xb0 };
        DBTVFrequency pictureCarrier = (_DVFormat == ntscIn ? 45750000 : 38900000); // FIXME: This should depend on color system, not DV format
        UInt16 freqCmd = ((freq + pictureCarrier) / 1000000.0) * 16.0;
        UInt16 bandCmd = 0;

        UInt16 firstI2C;
        UInt16 secondI2C;

        for (i = 0; i < bandsCount; i++) {
            band = [bands objectAtIndex:i];
            if (freq < [[band objectForKey:DBTunerMaxFrequencyKey] intValue]) {
                bandCmd = [[band objectForKey:DBTunerOpcodeKey] intValue];
                break;
            }
        }

        // ordering the commands per FI1216MF doc, page 16
        if (freq < _supposedCurrentFrequency) {
            firstI2C = bandCmd;
            secondI2C = freqCmd;
        } else {
            firstI2C = freqCmd;
            secondI2C = bandCmd;
        }

        if ([self firmwareVersion] >= 0x02010100) {
            *(UInt16 *)(cmd + 5) = EndianU16_NtoB(firstI2C);
            *(UInt16 *)(cmd + 7) = EndianU16_NtoB(secondI2C);
            [self doAVCCommand:IFcmd length:12];
            [self doAVCCommand:cmd length:12];
        } else {
            *(UInt16 *)(cmd + 2) = ([self firmwareVersion] < 0x02000000 ? EndianU16_NtoB(0x0103) : EndianU16_NtoB(0x01a1));
            *(UInt16 *)(cmd + 4) = EndianU16_NtoB(firstI2C);
            [self doAVCCommand:(UInt8 *)cmd length:8];
            *(UInt16 *)(cmd + 4) = EndianU16_NtoB(secondI2C);
            [self doAVCCommand:(UInt8 *)cmd length:8];
        }
        _supposedCurrentFrequency = freq;
    }
}

- (void)setRadioFrequency:(DBTVFrequency)freq
{
    if ([self hasRadioTuner]) {
        NSDictionary *radio = [_tunerInfo objectForKey:DBTunerRadioKey];
        UInt16 cmd[4] = { EndianU16_NtoB(0x00ab) };
        DBTVFrequency carrier = 10700000;
        UInt16 freqCmd = ((freq + carrier) / 1000000.0) * 20.0;
        UInt16 bandCmd = [[radio objectForKey:DBTunerOpcodeKey] intValue];

        cmd[1] = ([self firmwareVersion] < 0x02000000 ? EndianU16_NtoB(0x0103) : EndianU16_NtoB(0x01a1));

        cmd[2] = EndianU16_NtoB(bandCmd);
        [self doAVCCommand:(UInt8 *)cmd length:8];

        cmd[2] = EndianU16_NtoB(freqCmd);
        [self doAVCCommand:(UInt8 *)cmd length:8];

        _supposedCurrentFrequency = 0;
    }
}

- (void)setVolume:(int)volume
{
    SndCommand cmd;
    _volume = volume;
    if (_soundStarted) {
        cmd.param2 = (volume << 16) | volume;
        cmd.cmd = volumeCmd;
        SndDoCommand(_soundChannel, &cmd, YES);
    }
}

- (int)volume
{
    return _volume;
}

- (DBDVFrameInfoPtr)currentlyPlaying
{
    return _currentlyPlaying->frameInfo;
}

- (BOOL)deviceAdded:(DVDeviceID)deviceID
{
    OSErr err = noErr;
    UInt32 standard;
    BOOL added = NO;

    // do we need a device?
    if (![self hasDevice]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:DBVidiDisableRobustAVCResponseMatchingSettingName])
            disableRobustAVCResponseMatching();

        err = sDVFuncs.fDVOpenDriver(deviceID, &_deviceRefNum);
        if (err)
            goto error;

        err = sDVFuncs.fDVGetDeviceStandard(_deviceRefNum, &standard);
        if (err)
            goto error;

        _DVFormat = (standard==kPALStandard ? palIn : ntscIn);
        _frameSize = (standard==kPALStandard ? 144000 : 120000);

        [self getTunerInfo];
                
        DBDVFrameInfoPtr frameInfo;
        short i;
        void *memPtr;
        int sharedMemorySize;

        sharedMemorySize = sizeof(DBDVGrabberSharedMemory) + [self bufferCount] * (_frameSize + sizeof(DBDVFrameInfo));
        if (_isLogging)
            NSLog(@"sharedMemorySize = %d", sharedMemorySize);
        err = shm_unlink("com.mitzpettel.Vidi.mem");
        if (_isLogging)
            NSLog(@"unlink err: %d; errno: %d", err, errno);
        _sharedMemoryFile = shm_open("com.mitzpettel.Vidi.mem", O_RDWR|O_CREAT, 0666);
        if (_isLogging)
            NSLog(@"_sharedMemoryFile = %d", _sharedMemoryFile);            
        err = ftruncate(_sharedMemoryFile, sharedMemorySize);
        if (_isLogging)
            NSLog(@"ftruncate err: %d; errno: %d", err, errno);
        _sharedMemory = mmap(0, sharedMemorySize, PROT_READ | PROT_WRITE, MAP_SHARED, _sharedMemoryFile, 0);
        if (_isLogging)
            NSLog(@"_sharedMemory: %x", _sharedMemory);
        err = mlock(_sharedMemory, sharedMemorySize);
        if (err && _isLogging)
            NSLog(@"mlock() failed with errno: %d", errno);
        err = 0;
        
        _sharedMemory->baseAddress = _sharedMemory;
        memPtr = _sharedMemory->buffer;
        _sharedMemory->currentlyPlayingFrame = 0;

        for (i = 0; i < [self bufferCount]; i++) {
            frameInfo = memPtr;
            memPtr += sizeof(DBDVFrameInfo);
            frameInfo->frameBuffer = memPtr;
            memPtr += _frameSize;
            frameInfo->sndHead = malloc(sizeof(ScheduledSoundHeader));
    
            frameInfo->sndHead->u.cmpHeader.sampleRate = rate32khz;
            frameInfo->sndHead->u.cmpHeader.loopStart = 0;
            frameInfo->sndHead->u.cmpHeader.loopEnd = 0;
            frameInfo->sndHead->u.cmpHeader.encode = cmpSH;
            frameInfo->sndHead->u.cmpHeader.baseFrequency = 0x3f;
            frameInfo->sndHead->u.cmpHeader.numChannels = 2;
            frameInfo->sndHead->u.cmpHeader.sampleSize = 16;             
            frameInfo->sndHead->u.cmpHeader.packetSize = 16;   
            frameInfo->sndHead->u.cmpHeader.format = 'dvca';
            frameInfo->sndHead->u.cmpHeader.compressionID = -1;    
            frameInfo->sndHead->u.cmpHeader.samplePtr = frameInfo->frameBuffer;
            frameInfo->freeQElem = malloc(sizeof(DBFrameQElem));
            ((DBFrameQElemPtr)frameInfo->freeQElem)->frameInfo = frameInfo;
            frameInfo->playQElem = malloc(sizeof(DBFrameQElem));
            ((DBFrameQElemPtr)frameInfo->playQElem)->frameInfo = frameInfo;
            frameInfo->writeQElem = malloc(sizeof(DBFrameQElem));
            ((DBFrameQElemPtr)frameInfo->writeQElem)->frameInfo = frameInfo;
            Enqueue( frameInfo->freeQElem, &(_freeForWriting) );
            frameInfo->needsPlaying = NO;
            frameInfo->needsWriting = NO;
        }
        added = YES;
        _numFullBuffers = 0;
        _deviceID = deviceID;
        _deviceHasAVC = YES;
    }

error:
    if (err)
        [NSException raise:DBDVErrorException format:@"-[DBDVGrabber deviceAdded:] encountered error %d(0x%x).", err, err];
    if (added)
        [self getBrightness:&_brightness contrast:&_contrast saturation:&_saturation hue:&_hue];
    if (added && _delegate && [_delegate respondsToSelector:@selector(grabberDidAcquireDevice:)])
        [_delegate grabberDidAcquireDevice:self];
    if (_isLogging)
        NSLog(@"-[DBDVGrabber deviceAdded:%d] : %d", deviceID, added);
    return added;
}

- (void)deviceRemoved
{
    DBFrameQElemPtr frameQElem;
    int returnCode;
    
    if (_isLogging)
        NSLog(@"-[DBDVGrabber deviceRemoved]");

    if (_deviceID == kInvalidDVDeviceID)
        return;

    [_tunerInfo release];
    _tunerInfo = nil;
    _firmwareVersion = 0;
    _deviceID = kInvalidDVDeviceID;
    _deviceHasAVC = NO;
    if ([self isGrabbing])
        [self stopGrabbing];
    while (frameQElem = (DBFrameQElemPtr)(_freeForWriting.qHead)) {
        Dequeue((QElemPtr)frameQElem, &_freeForWriting);
        free(frameQElem->frameInfo->sndHead);
        free(frameQElem->frameInfo->playQElem);
        free(frameQElem->frameInfo->writeQElem);
    }
    returnCode = munmap(_sharedMemory, sizeof(DBDVGrabberSharedMemory) + [self bufferCount] * (_frameSize + sizeof(DBDVFrameInfo)));
    if (returnCode)
        goto error;
    
    _sharedMemory = NULL;
    returnCode = close(_sharedMemoryFile);
    if (returnCode)
        goto error;

    _sharedMemoryFile = 0;
    if (_delegate && [_delegate respondsToSelector:@selector(grabberDidLoseDevice:)])
        [_delegate grabberDidLoseDevice:self];

error:
    if (returnCode != 0)
        [NSException raise:DBDVErrorException format:@"-[DBDVGrabber deviceRemoved:] encountered error %d(0x%x).", errno, errno];
}

- (void)reader:(id)ignore
{
    OSErr err = noErr;
    OSErr wait;
    Ptr buffer;
    UInt32 count;
    void *frameBuffer;
    SndCommand cmd;
    DBFrameQElemPtr frameQElem;

    [_readerLock lock];

    // more or less copied from DVLib.c
    double mult;
    unsigned int delta;
    unsigned int abs_to_ns_num;
    unsigned int abs_to_ns_denom;
    unsigned int proc_to_abs_num;
    unsigned int proc_to_abs_denom;
    thread_time_constraint_policy_data_t constraints;
    kern_return_t result;
    // Set thread to Real Time

    MKGetTimeBaseInfo(&delta, &abs_to_ns_num, &abs_to_ns_denom, &proc_to_abs_num, &proc_to_abs_denom);

    mult = ((double)abs_to_ns_denom / (double)abs_to_ns_num) * 1000000;
    constraints.period = 12 * mult;
    constraints.computation = 2 * mult;
    constraints.constraint = 24 * mult;
    constraints.preemptible = TRUE;
    result = thread_policy_set(mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&constraints, THREAD_TIME_CONSTRAINT_POLICY_COUNT);




    if (_isLogging)
        NSLog(@"_readerLock locked");
    while (_isGrabbing) {
        wait = sDVFuncs.fDVReadFrame(_deviceRefNum, &buffer, &count);
        while (_isGrabbing && wait == -1) {
            usleep(10000);	// 10 milliseconds
            wait = sDVFuncs.fDVReadFrame(_deviceRefNum, &buffer, &count);
        }

        if (wait == -1) {
            // we got pulled out of waiting
            err = 0;
            goto error;
        }

        if (wait) {
            // some other error
            err = wait;
            goto error;
        }

        frameBuffer = buffer;
        frameQElem = (DBFrameQElemPtr)(_freeForWriting.qHead);
        if (_framesToDrop)
            _framesToDrop--;
        else if (frameQElem) {
            unsigned char audioType;

            Dequeue((QElemPtr)frameQElem, &_freeForWriting);
            _numFullBuffers++;

            bcopy(frameBuffer, frameQElem->frameInfo->frameBuffer, count);

            audioType = *((unsigned char *)(frameQElem->frameInfo->frameBuffer) + 4327) & 0x38;
            if (_firmwareVersion != 0 && _firmwareVersion < 0x01000800 && audioType == 0x10) {
                if (_DVFormat == palIn)
                    silenceChannel2(frameQElem->frameInfo->frameBuffer);
                else
                    silenceChannel2NTSC(frameQElem->frameInfo->frameBuffer);
            }

            if (_audioEnabled) {
                (frameQElem->frameInfo->sndHead)->u.cmpHeader.numFrames = 1;
                switch (audioType) {
                    case 0x00:	// 48.0kHz
                        (frameQElem->frameInfo->sndHead)->u.cmpHeader.sampleRate = rate48khz;
                        break;
                    case 0x08:	// 44.1kHz
                        (frameQElem->frameInfo->sndHead)->u.cmpHeader.sampleRate = rate44khz;
                        break;
                    case 0x10:	// 32.0kHz
                        (frameQElem->frameInfo->sndHead)->u.cmpHeader.sampleRate = rate32khz;
                        break;
                    default:
                        break;
                }
            }

            frameQElem->frameInfo->needsPlaying = (_audioEnabled && _numToBePlayed < 3);
            frameQElem->frameInfo->needsWriting = _isRecording;

            if (frameQElem->frameInfo->needsPlaying) {
                Enqueue(frameQElem->frameInfo->playQElem, &_toBePlayed);
                _numToBePlayed++;
            }

            Enqueue(frameQElem->frameInfo->writeQElem, &_toBeWritten);

            if (!_soundStarted && frameQElem->frameInfo->needsPlaying) {
                cmd.cmd = bufferCmd;
                cmd.param1 = 0;
                cmd.param2 = (long)frameQElem->frameInfo->sndHead;
                err = SndDoCommand(_soundChannel, &cmd, YES);
                cmd.cmd = callBackCmd;
                cmd.param2 = (long)self;
                err = SndDoCommand(_soundChannel, &cmd, YES);

                _soundStarted = YES;
                cmd.param2 = (_volume << 16) | _volume;
                cmd.cmd = volumeCmd;
                SndDoCommand(_soundChannel, &cmd, YES);
            }
        } else
            [self performSelectorOnMainThread:@selector(readerRanOutOfBuffers:) withObject:nil waitUntilDone:NO];

        err = sDVFuncs.fDVReleaseFrame(_deviceRefNum, buffer);
        if (err)
            goto error;
    }

error:
    if (err)
        [NSException raise:DBDVErrorException format:@"-[DBDVGrabber reader:] encountered error %d(0x%d).", err, err];

    if (_isLogging)
        NSLog(@"_readerLock unlocked");
    [_readerLock unlock];
}

- (BOOL)isAudioEnabled
{
    return _audioEnabled;
}

- (void)setAudioEnabled:(BOOL)flag
{
    _audioEnabled = flag;
}

- (unsigned)bufferCount
{
    return 25;
}

@end

static pascal void soundCallback(SndChannelPtr theChannel, SndCommand * theCallBackCmd)
{
    OSErr err;
    SndCommand cmd;
    DBFrameQElemPtr frameQElem;
    DBDVGrabber *grabber = (DBDVGrabber *)theCallBackCmd->param2;

    if (grabber->_soundStarted) {
        if (grabber->_currentlyPlaying) {
            grabber->_currentlyPlaying->frameInfo->needsPlaying = NO;
            if (grabber->_currentlyPlaying->frameInfo->timesPainted == 0)
                grabber->_sharedMemory->numUnpainted++;
            grabber->_currentlyPlaying = NULL;
        }

        // now get a buffer to play
        frameQElem = (DBFrameQElemPtr)(grabber->_toBePlayed.qHead);
        
        if (frameQElem) {
            frameQElem->frameInfo->timesPainted = 0;
            grabber->_currentlyPlaying = frameQElem;
            grabber->_sharedMemory->currentlyPlayingFrame = frameQElem->frameInfo;
            Dequeue((QElemPtr)frameQElem, &(grabber->_toBePlayed));
            grabber->_numToBePlayed--;
            cmd.cmd = bufferCmd;
            cmd.param1 = 0;
            cmd.param2 = (long)frameQElem->frameInfo->sndHead;
            err = SndDoCommand(theChannel, &cmd, YES);

            cmd.cmd = callBackCmd;
            cmd.param2 = (long)grabber;
            err = SndDoCommand(theChannel, &cmd, YES);
        } else {
            grabber->_sharedMemory->currentlyPlayingFrame = NULL;
            grabber->_soundStarted = false;
            cmd.cmd = volumeCmd;
            cmd.param2 = 0;
            err = SndDoCommand(theChannel, &cmd, YES);
        }
    }
}
