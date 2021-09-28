//
//  FATimeUtil.h
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/27.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FATimeUtil : NSObject

+ (void)begin:(NSString *)name;

+ (CFAbsoluteTime)end:(NSString *)name;

+ (CFAbsoluteTime)end:(NSString *)name log:(BOOL)log;


@end

NS_ASSUME_NONNULL_END
