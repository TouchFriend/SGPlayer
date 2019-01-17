//
//  SGPacket+Internal.h
//  SGPlayer iOS
//
//  Created by Single on 2018/10/23.
//  Copyright © 2018 single. All rights reserved.
//

#import "SGPacket.h"
#import "SGFFmpeg.h"
#import "SGAudioDescription.h"
#import "SGVideoDescription.h"

NS_ASSUME_NONNULL_BEGIN

@interface SGAudioDescription ()

- (instancetype)initWithFrame:(AVFrame *)frame;

@end

@interface SGVideoDescription ()

- (instancetype)initWithFrame:(AVFrame *)frame;

@end

NS_ASSUME_NONNULL_END