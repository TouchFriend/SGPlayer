//
//  SGGLView.h
//  SGPlayer
//
//  Created by Single on 2018/1/24.
//  Copyright © 2018年 single. All rights reserved.
//

#import "SGPLFGLView.h"

@interface SGGLView : SGPLFGLView

- (void)display:(void(^)(void))prepare;
- (void)clear;

@end