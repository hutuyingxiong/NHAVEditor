//
//  NHAVEditor.m
//  MBProgressHUD
//
//  Created by XiuDan on 2019/8/3.
//

#import "NHAVEditor.h"
#import "NHMediaCommandProtocol.h"
#import "NHAddAudioCommand.h"
#import "NHAddWatermarkCommand.h"
#import "NHMediaExportCommand.h"
#import "NSDate+NH.h"
#import "NHAVEditorHeader.h"


@interface NHAVEditor ()<NHMediaCommandProtocol>
@property (nonatomic, copy  ) NSURL *audioUrl;
@property (nonatomic, strong) CALayer *waterMLayer;
@property (nonatomic, copy  ) NSURL *_Nullable outputURL;
/** 合成状态 */
@property (nonatomic, assign) BOOL isCompositioning;
@property (nonatomic, assign) CGFloat currentProgress;
/** 是否取消了合成 */
@property (nonatomic, assign) BOOL isCancelComposition;
@property (nonatomic, strong) dispatch_queue_t compositionQueue;
@property (nonatomic, strong) AVAsset *vInputAsset;
@property (nonatomic, strong) AVMutableComposition *composition;
@property (nonatomic, strong) AVMutableVideoComposition *videoComposition;
@property (nonatomic, strong) AVMutableAudioMix *audioMix;
@property (nonatomic, strong) NHAddAudioCommand *audioCommand;
@property (nonatomic, strong) NHAddWatermarkCommand *watermarkCommand;
@property (nonatomic, strong) NHMediaExportCommand *exportCommand;
@property (nonatomic, copy  ) NHEditCompletedBlock mediaCommandCompletedBlock;
/** 视频导出质量 default：AVAssetExportPreset1280x720 */
@property (nonatomic, assign) NSString *exportPresetName;
/** 视频导出的文件类型 default：AVFileTypeQuickTimeMovie */
@property (nonatomic, copy  ) AVFileType outputFileType;

@end

@implementation NHAVEditor

- (instancetype)init {
  self = [super init];
  if (self) {
    [self initAvEditorConfig];
  }
  return self;
}

- (instancetype)initWithVideoURL:(NSURL *)videoURL {
  self = [super init];
  if (self) {
    [self setInputVideoURL:videoURL];
    [self initAvEditorConfig];
  }
  return self;
}

+ (instancetype)editorVideoURL:(NSURL *)videoURL {
  NHAVEditor *avEditor = [[NHAVEditor alloc] initWithVideoURL:videoURL];
  return avEditor;
}

#pragma mark - private method
#pragma mark -
- (void)initAvEditorConfig {
  _compositionQueue = dispatch_queue_create("com.nh.av.editor", DISPATCH_QUEUE_SERIAL);

  
}

- (void)setInputVideoURL:(NSURL *)inputVideoURL {
  if (inputVideoURL) {
    _vInputAsset = [AVAsset assetWithURL:inputVideoURL];
  } else {
    _vInputAsset = nil;
  }
}


#pragma mark - Media Command
#pragma mark -
- (void)addWatermarkWithLayer:(CALayer *)layer
                 customConfig:(void(^_Nullable)(NHWatermarkConfig *config))customConfig
               completedBlock:(NHEditCompletedBlock)completedBlock {
  NHWatermarkConfig *config = nil;
  if (customConfig) {
    config = [[NHWatermarkConfig alloc] init];
    customConfig(config);
  }
  
  if (completedBlock) {
    self.mediaCommandCompletedBlock = completedBlock;
  }
  _waterMLayer = layer;
  [self addWatermark:config];
}

- (void)addAudioWithAudioURL:(NSURL *)audioURL customConfig:(void (^_Nullable)(NHAudioConfig * _Nonnull))customConfig completedBlock:(NHEditCompletedBlock)completedBlock {
  NHAudioConfig *config = nil;
  if (customConfig) {
    config = [[NHAudioConfig alloc] init];
    customConfig(config);
  }
  
  if (completedBlock) {
    self.mediaCommandCompletedBlock = completedBlock;
  }
  _audioUrl = audioURL;
  [self addAudio:config];
}

- (void)exportMediaWithOutputURL:(NSURL *_Nullable)outputURL
                    customConfig:(void(^_Nullable)(NHExporyConfig *config))customConfig
                  completedBlock:(NHEditCompletedBlock)completedBlock {
  [self setOutputURL:outputURL];
  NHExporyConfig *config = nil;
  if (customConfig) {
    config = [[NHExporyConfig alloc] init];
    customConfig(config);
  }
  if (completedBlock) {
    self.mediaCommandCompletedBlock = completedBlock;
  }
  [self exportMedia:config];
}

- (void)addAudio:(NHAudioConfig *)config {
  if ([self checkInputAsset]) {
    _isCancelComposition = NO;
    _audioCommand = [NHAddAudioCommand commandWithComposition:_composition
                                             videoComposition:_videoComposition
                                                     audioMix:_audioMix];
    _audioCommand.config          = config;
    _audioCommand.delegate        = self;
    _audioCommand.inputAudioURL   = _audioUrl;
    [_audioCommand performWithAsset:_vInputAsset];
  }
}

- (void)addWatermark:(NHWatermarkConfig *)config {
  if ([self checkInputAsset]) {
    _isCancelComposition = NO;
    _watermarkCommand = [NHAddWatermarkCommand commandWithComposition:_composition
                                                     videoComposition:_videoComposition
                                                             audioMix:_audioMix];
    _watermarkCommand.delegate       = self;
    _watermarkCommand.config         = config;
    _watermarkCommand.watermarkLayer = _waterMLayer;
    [_watermarkCommand performWithAsset:_vInputAsset];
  }
}

/**
 导出前准备动画层
 */
- (void)exportWillBegin {
  if (_waterMLayer) {
    CALayer *videoLayer = [CALayer layer];
    CALayer *animationLayer = [CALayer layer];
    CGRect frame = CGRectMake(0, 0, _videoComposition.renderSize.width, _videoComposition.renderSize.height);
    animationLayer.frame = frame;
    videoLayer.frame = frame;
    [animationLayer addSublayer:videoLayer];
    [animationLayer addSublayer:_waterMLayer];
    
    _videoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:animationLayer];
  }
}

- (void)exportMedia:(NHExporyConfig *)config {
  if ([self checkInputAsset]) {
    if (_isCancelComposition) {
      _isCompositioning = NO;
      _isCancelComposition = NO;
      return;
    }
    [self exportWillBegin];
    _exportCommand = [NHMediaExportCommand commandWithComposition:_composition
                                                 videoComposition:_videoComposition
                                                         audioMix:_audioMix];
    _exportCommand.delegate         = self;
    _exportCommand.config           = config;
    _exportCommand.outputURL        = _outputURL;
    [_exportCommand performWithAsset:_vInputAsset];
  }
}


/**
 检查视频源是否存在

 @return true 存在， false 不存在
 */
- (BOOL)checkInputAsset {
  if (!_vInputAsset) {
    if (self.delegate && [self.delegate respondsToSelector:@selector(editorCompositioned:outputURL:error:)]) {
      NSError *error = NH_ERROR(400, ERR_INFO(@"输入源为空，请确认你的视频输入地址", nil, nil));
      [self.delegate editorCompositioned:self outputURL:_outputURL error:error];
    }
    return NO;
  }
  return YES;
}

- (void)resetBeforeRestartingComposition {
  self.composition = nil;
  self.videoComposition = nil;
  self.audioMix = nil;
  self.currentProgress = 0.0;
}

- (void)cancelComposition {
  [_exportCommand.exportSession cancelExport];
  _isCancelComposition = YES;
}


#pragma mark - NHMediaCommandProtocol
#pragma mark -
- (void)mediaCompositioning:(NHMediaCommand *)editor progress:(CGFloat)progress {
  self.audioMix = editor.mAudioMix;
  self.composition = editor.mComposition;
  self.videoComposition = editor.mVideoComposition;
  self.currentProgress = progress;
  if (self.delegate && [self.delegate respondsToSelector:@selector(editorCompositioning:progress:)]) {
    [self.delegate editorCompositioning:self progress:progress];
  }
}

- (void)mediaCompositioned:(NHMediaCommand *)editor outputURL:(NSURL *)outputURL error:(NSError *)error {
  self.audioMix = editor.mAudioMix;
  self.composition = editor.mComposition;
  self.videoComposition = editor.mVideoComposition;
  
  if (_mediaCommandCompletedBlock) {
    _mediaCommandCompletedBlock(outputURL, error);
  }
  if (self.delegate && [self.delegate respondsToSelector:@selector(editorCompositioned:outputURL:error:)]) {
    [self.delegate editorCompositioned:self outputURL:outputURL error:error];
  }
}

- (void)mediaExportCompleted:(NHMediaCommand *)editor outputURL:(NSURL *)outputURL error:(NSError *)error {
  self.audioMix = editor.mAudioMix;
  self.composition = editor.mComposition;
  self.videoComposition = editor.mVideoComposition;
  
  if (_mediaCommandCompletedBlock) {
    _mediaCommandCompletedBlock(outputURL, error);
  }
  if (self.delegate && [self.delegate respondsToSelector:@selector(editorExportCompleted:outputURL:error:)]) {
    [self.delegate editorExportCompleted:self outputURL:outputURL error:error];
  }
}


/**
 设置导出路径

 @param outputURL outputURL description
 */
- (void)setOutputURL:(NSURL *_Nullable)outputURL {
  if (outputURL) {
    _outputURL = outputURL;
  } else {
    NSString *name = [NSString stringWithFormat:@"%@.mp4",[NSDate getNowTimeTimestamp]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSURL *url = [NSURL fileURLWithPath:path];
    _outputURL = url;
  }
  [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
}

@end
