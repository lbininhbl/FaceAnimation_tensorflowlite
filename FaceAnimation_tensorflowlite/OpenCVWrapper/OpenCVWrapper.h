//
//  OpenCVWrapper.h
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/13.
//

#import <UIKit/UIKit.h>


NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (instancetype)shared;

- (UIImage *)alignFaceImage:(UIImage *)image from:(NSArray *_Nullable)from to:(NSArray *_Nullable)to fromRow:(int)fromRow fromCol:(int)fromCol toRow:(int)toRow toCol:(int)toCol size:(CGSize)size;


- (NSArray<UIImage *> *)fusion:(NSArray *_Nullable)predictions mask:(NSArray *_Nullable)mask sourceImage:(UIImage *)sourceImage progress:(void(^)(float))progress;


+ (void)demo;

@end

NS_ASSUME_NONNULL_END
