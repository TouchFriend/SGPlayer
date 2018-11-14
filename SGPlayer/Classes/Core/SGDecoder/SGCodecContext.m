//
//  SGCodecContext.m
//  SGPlayer iOS
//
//  Created by Single on 2018/8/16.
//  Copyright © 2018 single. All rights reserved.
//

#import "SGCodecContext.h"
#import "SGTrack+Internal.h"
#import "SGPacket+Internal.h"
#import "SGFrame+Internal.h"
#import "SGConfiguration.h"
#import "SGObjectPool.h"
#import "SGMapping.h"
#import "SGError.h"
#import "SGMacro.h"

@interface SGCodecContext ()

@property (nonatomic, assign) AVCodecContext * codecContext;
@property (nonatomic, strong) SGTrack * track;
@property (nonatomic, strong) Class frameClass;

@end

@implementation SGCodecContext

static enum AVPixelFormat SGCodecContextGetFormat(struct AVCodecContext * s, const enum AVPixelFormat * fmt)
{
    SGCodecContext * self = (__bridge SGCodecContext *)s->opaque;
    for (int i = 0; fmt[i] != AV_PIX_FMT_NONE; i++) {
        if (fmt[i] == AV_PIX_FMT_VIDEOTOOLBOX) {
            AVBufferRef * device_ctx = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_VIDEOTOOLBOX);
            if (!device_ctx) {
                break;
            }
            AVBufferRef * frames_ctx = av_hwframe_ctx_alloc(device_ctx);
            av_buffer_unref(&device_ctx);
            if (!frames_ctx) {
                break;
            }
            AVHWFramesContext * frames_ctx_data = (AVHWFramesContext *)frames_ctx->data;
            frames_ctx_data->format = AV_PIX_FMT_VIDEOTOOLBOX;
            frames_ctx_data->sw_format = SGPixelFormatAV2FF(self.preferredPixelFormat);
            frames_ctx_data->width = s->width;
            frames_ctx_data->height = s->height;
            int err = av_hwframe_ctx_init(frames_ctx);
            if (err < 0) {
                av_buffer_unref(&frames_ctx);
                break;
            }
            s->hw_frames_ctx = frames_ctx;
            return fmt[i];
        }
    }
    return fmt[0];
}

- (AVCodecContext *)createCcodecContext
{
    AVCodecContext * codecContext = avcodec_alloc_context3(NULL);
    if (!codecContext) {
        return nil;
    }
    codecContext->opaque = (__bridge void *)self;
    
    int result = avcodec_parameters_to_context(codecContext, self.track.core->codecpar);
    NSError * error = SGEGetError(result, SGOperationCodeCodecSetParametersToContext);
    if (error) {
        avcodec_free_context(&codecContext);
        return nil;
    }
    codecContext->pkt_timebase = self.track.core->time_base;
    if ((self.hardwareDecodeH264 && self.track.core->codecpar->codec_id == AV_CODEC_ID_H264) ||
        (self.hardwareDecodeH265 && self.track.core->codecpar->codec_id == AV_CODEC_ID_H265)) {
        codecContext->get_format = SGCodecContextGetFormat;
    }
    
    AVCodec * codec = avcodec_find_decoder(codecContext->codec_id);
    if (!codec) {
        avcodec_free_context(&codecContext);
        return nil;
    }
    codecContext->codec_id = codec->id;
    
    AVDictionary * opts = SGDictionaryNS2FF(self.options);
    if (self.threadsAuto &&
        !av_dict_get(opts, "threads", NULL, 0)) {
        av_dict_set(&opts, "threads", "auto", 0);
    }
    if (self.refcountedFrames &&
        !av_dict_get(opts, "refcounted_frames", NULL, 0) &&
        (codecContext->codec_type == AVMEDIA_TYPE_VIDEO || codecContext->codec_type == AVMEDIA_TYPE_AUDIO)) {
        av_dict_set(&opts, "refcounted_frames", "1", 0);
    }
    
    result = avcodec_open2(codecContext, codec, &opts);
    
    if (opts) {
        av_dict_free(&opts);
    }
    
    error = SGEGetError(result, SGOperationCodeCodecOpen2);
    if (error) {
        avcodec_free_context(&codecContext);
        return nil;
    }
    
    return codecContext;
}

- (instancetype)initWithTrack:(SGTrack *)track frameClass:(Class)frameClass
{
    if (self = [super init]) {
        self.options = [SGConfiguration defaultConfiguration].codecContextOptions;
        self.threadsAuto = [SGConfiguration defaultConfiguration].threadsAuto;
        self.refcountedFrames = [SGConfiguration defaultConfiguration].refcountedFrames;
        self.hardwareDecodeH264 = [SGConfiguration defaultConfiguration].hardwareDecodeH264;
        self.hardwareDecodeH265 = [SGConfiguration defaultConfiguration].hardwareDecodeH265;
        self.preferredPixelFormat = [SGConfiguration defaultConfiguration].preferredPixelFormat;
        self.track = track;
        self.frameClass = frameClass;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (BOOL)open
{
    if (!self.track) {
        return NO;
    }
    if (!self.frameClass) {
        return NO;
    }
    self.codecContext = [self createCcodecContext];
    if (!self.codecContext) {
        return NO;
    }
    return YES;
}

- (void)flush
{
    if (self.codecContext) {
        avcodec_flush_buffers(self.codecContext);
    }
}

- (void)close
{
    if (self.codecContext) {
        avcodec_close(self.codecContext);
        self.codecContext = nil;
    }
}

- (NSArray <__kindof SGFrame *> *)decode:(SGPacket *)packet
{
    if (!self.codecContext) {
        return nil;
    }
    int result = avcodec_send_packet(self.codecContext, packet ? packet.core : NULL);
    if (result < 0) {
        return nil;
    }
    NSMutableArray * array = nil;
    while (result != AVERROR(EAGAIN)) {
        __kindof SGFrame * frame = [[SGObjectPool sharePool] objectWithClass:self.frameClass];
        result = avcodec_receive_frame(self.codecContext, frame.core);
        if (result < 0) {
            [frame unlock];
            break;
        } else {
            if (!array) {
                array = [NSMutableArray array];
            }
            [frame configurateWithTrack:self.track];
            [array addObject:frame];
        }
    }
    return array;
}

@end