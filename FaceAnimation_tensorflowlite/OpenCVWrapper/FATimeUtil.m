//
//  FATimeUtil.m
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/27.
//

#import "FATimeUtil.h"

@interface FATimeUtil ()

@property (nonatomic, strong) NSMutableDictionary *events;

@end

@implementation FATimeUtil

+ (instancetype)shared {
    static FATimeUtil *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FATimeUtil alloc] init];
    });
    return shared;
}

+ (void)begin:(NSString *)name {
    CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
    [[FATimeUtil shared].events setValue:@(currentTime) forKey:name];
}

+ (CFAbsoluteTime)end:(NSString *)name log:(BOOL)log {
    CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime startTime = [[FATimeUtil shared].events[name] doubleValue];
    CFAbsoluteTime totalTime = currentTime - startTime;
    if (log) {
        NSLog(@"(%@)所花费的时间: %lfs", name, totalTime);
    }
    return totalTime;
}

+ (CFAbsoluteTime)end:(NSString *)name {
    return [self end:name log:NO];
}

#pragma mark - Getter
- (NSMutableDictionary *)events {
    if (!_events) {
        _events = [NSMutableDictionary dictionary];
    }
    return _events;
}

@end

