//
//  IQAudioRecorder.m
//  IQAudioRecorderController Demo
//
//  Created by Sebastian Ludwig on 09.07.15.
//  Copyright (c) 2015 Iftekhar. All rights reserved.
//

#import "IQAudioRecorder.h"

@interface IQAudioRecorder () <AVAudioRecorderDelegate, AVAudioPlayerDelegate>

@end

@implementation IQAudioRecorder
{
    AudioFormatID formatID;
    NSString *fileNameExtension;
    
    AVAudioRecorder *audioRecorder;
    AVAudioPlayer *audioPlayer;
    
    BOOL recordingIsPrepared;
    BOOL recordingStoppedManually;
    
    NSString *oldSessionCategory;
}

- (instancetype)init
{
    if (self = [super init]) {
        formatID = kAudioFormatMPEG4AAC;
        fileNameExtension = @"m4a";
        
        self.format = @"aac";
        self.sampleRate = 44100;
        self.channels = 2;
    }
    return self;
}

- (instancetype)initWithFormat:(AudioFormatID)format sampleRate:(CGFloat)sampleRate numberOfChannels:(int)channels
{
    if (self = [self init]) {
        formatID = format;
        self.sampleRate = sampleRate;
        self.channels = channels;
    }
    return self;
}

- (void)awakeFromNib
{
    [self setup];
}

- (void)setup
{
    if ([self.format isEqualToString:@"mp3"]) {
        formatID = kAudioFormatMPEGLayer3;
        fileNameExtension = @"mp3";
    }
    
    NSString *fileName = [[NSProcessInfo processInfo] globallyUniqueString];
    _filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", fileName, fileNameExtension]];
    
    oldSessionCategory = [[AVAudioSession sharedInstance] category];
    
    NSDictionary *recordSetting = @{AVFormatIDKey: @(formatID),
                                    AVSampleRateKey: @(self.sampleRate),
                                    AVNumberOfChannelsKey: @(self.channels)};
    
    NSError *error;
    audioRecorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_filePath]
                                                settings:recordSetting
                                                   error:&error];
    if (error) {
        [self notifyDelegateAboutError:error];
        return;
    }
    
    audioRecorder.delegate = self;
    audioRecorder.meteringEnabled = YES;
    
    
    if ([self isMicrophoneAccessGranted]) {
        // only prepare now, if microphone access is aready granted (otherwise the user will be asked out of context)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            [self prepareForRecording];
        });
    }
}

- (void)dealloc
{
    audioRecorder.delegate = nil;
    [audioRecorder stop];
    audioPlayer.delegate = nil;
    [audioPlayer stop];
    
    [[AVAudioSession sharedInstance] setCategory:oldSessionCategory error:nil];
}

- (BOOL)isMicrophoneAccessGranted
{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if ([session respondsToSelector:@selector(recordPermission)]) {
        return [session recordPermission] == AVAudioSessionRecordPermissionGranted;
    } else {
        return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
    }
}

- (CGFloat)updateMeters
{
    if (audioRecorder.isRecording) {
        [audioRecorder updateMeters];
        
        CGFloat normalizedValue = pow(10, [audioRecorder averagePowerForChannel:0] / 20);
        return normalizedValue;
    }
    else if (audioPlayer.isPlaying) {
        [audioPlayer updateMeters];
        
        CGFloat normalizedValue = pow(10, [audioPlayer averagePowerForChannel:0] / 20);
        return normalizedValue;
    }
    return 0;
}

- (NSTimeInterval)currentTime
{
    if (self.isRecording) {
        return audioRecorder.currentTime;
    }
    
    return audioPlayer.currentTime;
}

- (void)setCurrentTime:(NSTimeInterval)currentTime
{
    if (!self.isRecording) {
        audioPlayer.currentTime = currentTime;
    }
}

- (void)notifyDelegateAboutError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(audioRecorder:didFailWithError:)]) {
        [self.delegate audioRecorder:self didFailWithError:error];
    }
}

#pragma mark Recording

// HINT: at the moment this overwrites the current recording -> create new recorder with different URL?
- (void)prepareForRecording
{
    @synchronized(self) {
        if (recordingIsPrepared) {
            return;
        }
        
        NSError *error;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:&error];
        if (error) {
            [self notifyDelegateAboutError:error];
            return;
        }
        
        [audioRecorder prepareToRecord];
        recordingIsPrepared = YES;
    }
}

- (void)startRecording
{
    [self startRecordingForDuration:-1];
}

- (void)startRecordingForDuration:(NSTimeInterval)duration
{
    if (![self isMicrophoneAccessGranted]) {
        __weak typeof(self) weakSelf = self;
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            __strong typeof(self) strongSelf = weakSelf;
            if (granted) {
                [strongSelf startRecording];
            } else {
                if ([strongSelf.delegate respondsToSelector:@selector(microphoneAccessDeniedForAudioRecorder:)]) {
                    [strongSelf.delegate microphoneAccessDeniedForAudioRecorder:strongSelf];
                }
            }
        }];
        return;
    }
    
    [self prepareForRecording];
    
    if (duration <= 0) {
        [audioRecorder record];
    } else {
        [audioRecorder recordForDuration:duration];
    }
    
    @synchronized(self) {
        recordingIsPrepared = NO;
    }
}

- (void)stopRecording
{
    recordingStoppedManually = YES;
    [audioRecorder stop];
}

- (void)discardRecording
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:&error];
    if (error) {
        [self notifyDelegateAboutError:error];
        return;
    }
    
    [self prepareForRecording];
}

- (BOOL)isRecording
{
    return audioRecorder.isRecording;
}

#pragma mark Playback

- (NSTimeInterval)playbackDuration
{
    return audioPlayer.duration;
}

- (void)startPlayback
{
    // TODO: prevent playback while recording is running and vice versa
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        [self notifyDelegateAboutError:error];
        return;
    }
    
    @synchronized(self) {
        recordingIsPrepared = NO;
    }
    
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:self.filePath] error:&error];
    if (error) {
        [self notifyDelegateAboutError:error];
        return;
    }
    audioPlayer.delegate = self;
    audioPlayer.meteringEnabled = YES;
    [audioPlayer prepareToPlay];
    [audioPlayer play];
}

- (void)stopPlayback
{
    [audioPlayer stop];
}

- (void)pausePlayback
{
    [audioPlayer pause];
}

- (void)resumePlayback
{
    [audioPlayer play];
}

- (BOOL)isPlaying
{
    return audioPlayer.isPlaying;
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)successful
{
    if ([self.delegate respondsToSelector:@selector(audioRecorderDidFinishPlayback:successfully:)]) {
        [self.delegate audioRecorderDidFinishPlayback:self successfully:successful];
    }
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    [self notifyDelegateAboutError:error];
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)successfully
{
    if (!recordingStoppedManually && [self.delegate respondsToSelector:@selector(audioRecorderDidFinishRecording:successfully:)]) {
        [self.delegate audioRecorderDidFinishRecording:self successfully:successfully];
    }
    
    recordingStoppedManually = NO;
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error
{
    [self notifyDelegateAboutError:error];
}

@end
