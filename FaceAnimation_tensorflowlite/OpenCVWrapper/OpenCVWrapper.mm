//
//  OpenCVWrapper.m
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/13.
//

#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/core/types.hpp>
#import <opencv2/calib3d/calib3d_c.h>
#import "FATimeUtil.h"

using namespace std;
using namespace cv;

@interface OpenCVWrapper() {
    Mat _inv_mat; // 临时
    Mat _img_T; // 临时
    Mat _trans_mat;
}

@end

@implementation OpenCVWrapper

+ (instancetype)shared {
    static OpenCVWrapper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OpenCVWrapper alloc] init];
    });
    return instance;
}

+ (NSString *)openCVVersion {
    return [NSString stringWithFormat:@"OpenCV Version %s", CV_VERSION];
}


#pragma mark - Private
+ (Mat)matFrom:(UIImage *)source {
    cout << "matFrom ->";
    
    CGImageRef imageRef = CGImageCreateCopy(source.CGImage);
    
    CGFloat cols = CGImageGetWidth(imageRef);
    CGFloat rows = CGImageGetHeight(imageRef);
    
    Mat result(rows, cols, CV_8UC4, Scalar(1, 2, 3, 4));
    
    
    size_t bitsPercomponent = 8;
    size_t bytesPerRow = result.step[0];
    
    CGColorSpaceRef colorSpaceRef = CGImageGetColorSpace(imageRef);
    CGBitmapInfo bitmapInfo = kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault;
    
    CGContextRef context = CGBitmapContextCreate(result.data, cols, rows, bitsPercomponent, bytesPerRow, colorSpaceRef, bitmapInfo);
    CGContextDrawImage(context, CGRectMake(0, 0, cols, rows), imageRef);
    
    CGContextRelease(context);
    
    return result;
}

- (UIImage *)alignFaceImage:(UIImage *)image from:(NSArray *)from to:(NSArray *)to fromRow:(int)fromRow fromCol:(int)fromCol toRow:(int)toRow toCol:(int)toCol size:(CGSize)size {
   
    Mat imgMat;
    UIImageToMat(image, imgMat);
    cvtColor(imgMat, imgMat, COLOR_RGBA2BGRA);
    
    int **fromArray = [self getArrayFrom:from];
    int **toArray = [self getArrayFrom:to];
    
    Mat fromMat = [self Vec2Mat:fromArray type:CV_16U row:fromRow col:fromCol];
    Mat toMat = [self Vec2Mat:toArray type:CV_16U row:toRow col:toCol];
    
    free(fromArray);
    free(toArray);
    
    Mat trans_mat = estimateAffinePartial2D(fromMat, toMat);
    
    Mat img_T;
    warpAffine(imgMat, img_T, trans_mat, Size2i(size.width, size.height));
    _img_T = img_T;
    
    _trans_mat = trans_mat;
    
    // 再反过来
    Mat inv_mat;
    invertAffineTransform(_trans_mat, inv_mat);
    _inv_mat = inv_mat;
    
    UIImage *newImage = MatToUIImage(img_T);
    
    return newImage;
}

- (NSArray<UIImage *> *)fusion:(NSArray *)predictions mask:(NSArray *)mask sourceImage:(UIImage *)sourceImage progress:(nonnull void (^)(float))progress {
    
    Mat imgMat;
    UIImageToMat(sourceImage, imgMat);
    
    [FATimeUtil begin:@"mask 转 Mat"];
    Mat fusion_mask = [self getMatFromArray:mask];
    [FATimeUtil end:@"mask 转 Mat" log:YES];
    
    [FATimeUtil begin:@"alignedFace0 转精度"];
    Mat alignedFace0;
    cvtColor(_img_T, _img_T, COLOR_BGRA2RGBA);
    _img_T.convertTo(alignedFace0, CV_32FC4);
    alignedFace0 = alignedFace0 / 255.0;
    [FATimeUtil end:@"alignedFace0 转精度" log:YES];
    
    NSInteger totalCount = predictions.count;
    
    NSMutableArray<UIImage *> *frames = [NSMutableArray array];
    
    @autoreleasepool {
        
        [FATimeUtil begin:@"fuse"];
        
        [predictions enumerateObjectsUsingBlock:^(NSArray *_Nonnull predArr, NSUInteger idx, BOOL * _Nonnull stop) {
            
            [FATimeUtil begin:@"一次循环"];
            
//            float percent = idx * 1.0 / totalCount;
//            progress(percent);
            
            [FATimeUtil begin:@"pred 转 Mat"];
            Mat pred = [self getMatFromArray:predArr];
            [FATimeUtil end:@"pred 转 Mat" log:YES];
            
            
            [FATimeUtil begin:@"fuse 公式"];
            Mat n(fusion_mask.rows, fusion_mask.cols, fusion_mask.type(), Scalar(1, 1, 1, 1));
            Mat fuse_pred = fusion_mask.mul(pred) + (n - fusion_mask).mul(alignedFace0);
            [FATimeUtil end:@"fuse 公式" log:YES];
            
            [FATimeUtil begin:@"格式转换"];
            Mat fuse_pred_uint8;
            fuse_pred = fuse_pred * 255;
            fuse_pred.convertTo(fuse_pred_uint8, CV_8UC4);
            [FATimeUtil end:@"格式转换" log:YES];
            
            [FATimeUtil begin:@"warp"];
            warpAffine(fuse_pred_uint8, imgMat, _inv_mat, Size2i(sourceImage.size.width, sourceImage.size.height), INTER_LINEAR, BORDER_TRANSPARENT);
            [FATimeUtil end:@"warp" log:YES];
            
            [FATimeUtil begin:@"颜色格式转换"];
            Mat imgConvert;
            cvtColor(imgMat, imgConvert, COLOR_BGRA2RGBA);
            [FATimeUtil end:@"颜色格式转换" log:YES];
            
            [FATimeUtil begin:@"转UIImage"];
            UIImage *finalFrame = MatToUIImage(imgConvert);
            [frames addObject:finalFrame];
            [FATimeUtil end:@"转UIImage" log:YES];
            
            [FATimeUtil end:@"一次循环" log:YES];
            
            NSLog(@"");
        }];
        
        [FATimeUtil end:@"fuse" log:YES];
    }
    
    return frames.copy;
}

- (int **)getArrayFrom:(NSArray *)array {
    NSInteger count = array.count;
    int **p = (int **)malloc(count * sizeof(int *));
    
    for (int i = 0; i < count; i++) {
        
        NSArray<NSNumber *> *temp = array[i];
        int *temp_p = (int *)malloc(temp.count * sizeof(int));
        [temp enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            temp_p[idx] = [obj intValue];
        }];
        
        p[i] = temp_p;
    }
    return p;
}


- (Mat)getMatFromArray:(NSArray *)array {
    NSUInteger row = 256;
    NSUInteger col = 256;
    NSUInteger channel = 4;
    
    float *d1 = (float *)malloc(sizeof(float) * row * col * channel);
    
    // 这里不能顺着取
    for (NSUInteger i = 0; i < row; i++) {
        NSArray *rows = array[i];
        for (NSUInteger j = 0; j < col; j++) {
            NSArray *cols = rows[j];
            for (NSUInteger k = 0; k < channel; k++) {
                NSUInteger index = i * col * channel + j * channel + k;
                if (k == 3) {
                    d1[index] = 1.0;
                } else {
                    float value = [cols[k] floatValue];
                    d1[index] = value;
                }
            }
        }
    }
    
    int type = channel == 4 ? CV_32FC4 : CV_32FC3;
    Mat b(Size2l(row, col), type, d1);
    
//    free(d1);
    
    return b;
}

- (Mat)Vec2Mat:(int **)array type:(int)type row:(int)row col:(int)col {
    Mat mat(row, col, type);
    
    UInt16 *ptemp = NULL;
    
    for (int i = 0; i < row; i++) {
        ptemp = mat.ptr<UInt16>(i);
        for (int j = 0; j < col; j++) {
            ptemp[j] = array[i][j];
        }
    }
    
    return mat;
}

- (void)enumMat:(Mat)mat {
    cout << mat << endl;
}

+ (void)demo {
}



@end
