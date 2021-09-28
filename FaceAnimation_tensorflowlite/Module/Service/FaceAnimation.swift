//
//  FaceAnimation.swift
//  FaceAnimation_tensorflowlite
//
//  Created by zhangerbing on 2021/9/27.
//

import Foundation
import RxSwift

struct FaceAnimation {
    
    private var driving_motion_kps: [[String: Any]]!
    private var stdFace: [[Int]]!
    private var fusion_mask: [[[Float]]]!
    private var fps: Int = 15
    
    init() {
        // 初始化需要的数据
//        let driving_kp_name = "myh-fps15"
        let driving_kp_name = "myh-L-fps15"
        let fusion_mask_name = "fusion_mask"
        let stdFace_name = "male_std-landmarks"
        
        driving_motion_kps = FileUtils.load(name: driving_kp_name, type: "json") as? [[String: Any]]
        
        fusion_mask = (FileUtils.load(name: fusion_mask_name, type: "json") as? [[[NSNumber]]])?.compactMap({ $0.compactMap { $0.compactMap { $0.floatValue } } })
        
        stdFace = FileUtils.load(name: stdFace_name, type: "json") as? [[Int]]
        
        let fpsString = driving_kp_name.components(separatedBy: "-").last!
        fps = fpsString[(fpsString.count-2)...].intValue()
        
    }
    
    func execute(image: UIImage?) -> Observable<URL> {
        
        guard let image = image else {
            return Observable.create { observer in
                let error = NSError(domain: "data nil", code: -1, userInfo: [NSLocalizedDescriptionKey: "input image is nil"])
                observer.on(.error(error))
                return Disposables.create()
            }
        }
        
        let sourceImageSize = image.size
        
        // 1. 人脸识别处理
        TimeUtil.begin("face")
        guard let alignedFaceBuffer = detect_face(image: image)?.pixelBuffer() else {
            return Observable.create { observer in
                let error = NSError(domain: "data nil", code: -2, userInfo: [NSLocalizedDescriptionKey: "no face"])
                observer.on(.error(error))
                return Disposables.create()
            }
        }
        TimeUtil.end("face", log: "人脸处理所花的时间")
        
        // 2. 获取原图的运动关键点
        let kp_result = kp_dectector(with: alignedFaceBuffer)
        
        // 使用视频第一帧作为参考帧
        let init_val_arr = (driving_motion_kps[0]["value"] as! [[NSNumber]]).map { $0.map { $0.floatValue } }
        let init_val = init_val_arr.flatMap { $0 }
        let init_jac_arr = (driving_motion_kps[0]["jacobian"] as! [[[NSNumber]]]).map { $0.map { $0.map { $0.floatValue } } }
        let init_jac = init_jac_arr.flatMap { $0.flatMap { $0 } }
        
        // 3. 归一化视频运动关键点
        let kp_drv_norm = kp_normalize(with: kp_result, init_val: init_val, init_jac: init_jac)
        
        // 4. 生成动画帧
        let predictions = generator(with: kp_result, kp_drv_norm: kp_drv_norm, faceBuffer: alignedFaceBuffer)
        
        // 5. 进行图像融合
        TimeUtil.begin("fuse")
        let finalFrames = OpenCVWrapper.shared().fusion(predictions, mask: fusion_mask, sourceImage: image) { progress in
            let text = String(format: "将预测的图片融合到原图上, 进度%.2f%%", progress * 100.0)
            print(text)
        }
        TimeUtil.end("fuse", log: "融合图像所花的时间")
        
        // 6. 生成视频
        TimeUtil.begin("composition")
        let url = makeMovie(with: finalFrames, size: sourceImageSize, fps: fps)
        TimeUtil.end("composition", log: "合成视频所花的时间")
        
        return url
    }
    
    @discardableResult
    func predict_box(width: CGFloat, height: CGFloat, confidences: [[Float]], boxes: [[Float]], prob_threshold: Float = 0.9 , iou_threshold: Float = 0.5, top_k: Int = -1) -> (confidences: [Float], boxes: [[Float]]) {
        // 取出confidence大于prob_threshold的值，以对应的box
        var subBox = [[Float]]()
        var probs = [Float]()
        for (index, confidence) in confidences.enumerated() {
            if confidence[1] > prob_threshold {
                probs.append(confidence[1])
                subBox.append(boxes[index])
            }
        }
        
        guard probs.count > 0 else { return ([], []) }
        
        // 进行非极大值抑制，选出分数最高的框
        let nms_result = FaceUtils.hard_nms(scores: probs, boxes: subBox)
        
        // 计算出框框在原图中的位置
        let probs_box = nms_result.boxes.map { box in
            box.enumerated().map { boxitem in
                boxitem.offset % 2 == 0 ? boxitem.element * Float(width) : boxitem.element * Float(height)
            }
        }
        
        return (nms_result.confidence, probs_box)
    }
    
    func detect_face(image: UIImage) -> UIImage? {
        guard let faceDetector = FaceDetector(model: .faceDetector), let faceKpDetector = FaceKeyPointDetector(model: .faceKeypoint) else { return nil }
        
        guard let pixelBuffer = image.pixelBuffer() else {
            print("图像转pixelBuffer失败")
            return nil
        }

        let sourceImageSize = image.size
        // 1. 模型返回处理过的元组数据([4420, 2], [4420, 4])
        let face_result = faceDetector.runModel(onFrame: pixelBuffer) as! (configdences: [[Float]], boxes: [[Float]])
        let confidences = face_result.configdences
        let boxes = face_result.boxes
        
        // 2. 选出人脸预测框
        let faceDetectResult = predict_box(width: sourceImageSize.width, height: sourceImageSize.height, confidences: confidences, boxes: boxes)
        
        guard faceDetectResult.boxes.count > 0 else {
            print("没有检测到人脸")
            return nil
        }
        // MARK: - 人脸对齐
        print("目前只支持1张人脸，默认取检测到的第一张人脸")
        
        let box = faceDetectResult.boxes[0]
        
        // 1. 进行人脸关键点检测
        guard let face = image.crop(to: box) else { return nil }
        guard let faceBuffer = face.pixelBuffer() else { return nil }
        let points = faceKpDetector.runModel(onFrame: faceBuffer) as! [Float]
        let landmark = reformLandmarks(with: points, box: box, source_image_size: sourceImageSize)
        
        // 2. 进行人脸对齐
        let alignedFace0 = OpenCVWrapper.shared().alignFace(image,
                                                            from: landmark as [Any],
                                                            to: stdFace!,
                                                            fromRow: Int32(landmark.count),
                                                            fromCol: Int32(landmark[0].count),
                                                            toRow: Int32(stdFace.count),
                                                            toCol: Int32(stdFace[0].count),
                                                            size: CGSize(width: 256, height: 256))
        
        return alignedFace0
    }
    
    func kp_dectector(with faceBuffer: CVPixelBuffer) -> (values: [Float], jacobian: [Float]) {
        guard let kpDetector = KPDetector(model: .kp_detect) else { fatalError("kp detector 创建失败") }
        TimeUtil.begin("kp_detector")
        let kp_result = kpDetector.runModel(onFrame: faceBuffer) as! (values: [Float], jacobian: [Float])
        TimeUtil.end("kp_detector", log: "kp detector所花的时间")
        return kp_result
    }
    
    func kp_normalize(with kp_result: (values: [Float], jacobian: [Float]), init_val: [Float], init_jac: [Float]) -> [(values: [Float], jacobian: [Float])] {
        
        guard let kpProcessor = KPProcessor(model: .kp_process) else { fatalError("kp processor 创建失败") }
        
        // 归一化视频运动关键点
        print("Normalizing kps...")
        
        var kp_drv_norm = [(values: [Float], jacobian: [Float])]()
        
        autoreleasepool {
            TimeUtil.begin("normalize_kp")
            for driving_kp in driving_motion_kps {
                autoreleasepool {
                    let jac_arr = (driving_kp["jacobian"] as! [[[NSNumber]]]).map { $0.map { $0.map { $0.floatValue } } }
                    let jac = jac_arr.flatMap { $0.flatMap { $0 } }
                    let val_arr = (driving_kp["value"] as! [[NSNumber]]).map { $0.map { $0.floatValue } }
                    let val = val_arr.flatMap { $0 }
                    
                    let kp_norm = kpProcessor.runModelFlat(with: val, jacobian: jac, init_value: init_val, init_jacobian: init_jac, kp_value: kp_result.values, kp_jacobian: kp_result.jacobian) as! (values: [Float], jacobian: [Float])
                    kp_drv_norm.append(kp_norm)
                }
            }
            TimeUtil.end("normalize_kp", log: "normailze kp所花的时间")
        }
        
        return kp_drv_norm
    }
    
    @discardableResult
    func generator(with kp_result: (values: [Float], jacobian: [Float]), kp_drv_norm: [(values: [Float], jacobian: [Float])], faceBuffer: CVPixelBuffer) -> [[[[Float]]]] {
        guard let generator = Generator(model: .generator) else { fatalError("generator 创建失败") }
        
        var predictions = [[[[Float]]]]()
        // 4. 开始生成动画
        TimeUtil.begin("generator")
        print("开始生成人脸图像帧...")
        autoreleasepool {
            let count = kp_drv_norm.count
            for (index, kp_drv) in kp_drv_norm.enumerated() {
                autoreleasepool {
                    let text = String(format: "生成人脸图像帧,进度:%.2f%%", (Float(index) / Float(count)) * 100.0)
                    print(text)
                    let prediction = generator.runModelFlat(onFrame: faceBuffer, values: kp_drv.values, jacobian: kp_drv.jacobian, kp_value: kp_result.values, kp_jacobian: kp_result.jacobian) as! [[[Float]]]
                    predictions.append(prediction)
                }
            }
        }
        TimeUtil.end("generator", log: "generator 所花的时间")
        
        return predictions
    }
    
    func reformLandmarks(with points: [Float], box: [Float], source_image_size: CGSize) -> [[Int]] {
        let w = source_image_size.width
        let h = source_image_size.height
        
        let face_start_ij = (box[1], box[0])
        let face_h = box[3] - box[1]
        let face_w = box[2] - box[0]
        
        // points 前一半都是坐标x，后一半都是坐标y
        let middle = points.count / 2
        let x = Array(points[..<middle]).map { Int($0 / 96.0 * face_h + face_start_ij.0) }.clamp(to: 0...(Int(h)-2))
        let y = Array(points[middle...]).map { Int($0 / 96.0 * face_w + face_start_ij.1) }.clamp(to: 0...(Int(w)-2))
        
        let zipArray = Array(zip(y, x)).map { [$0.0, $0.1] }
        return zipArray
    }
    
    func makeMovie(with images: [UIImage], size: CGSize, fps: Int) -> Observable<URL> {
        let audioPath = Bundle.main.path(forResource: "myh-fps15", ofType: "mp3")!
        let audioUrl = URL(fileURLWithPath: audioPath)
        let duration = AssetUtils.durationOf(fileUrl: audioUrl)
        
        let path = FilePath.path(subPath: "/test1.mov", shouldClear: true)
        
        return Observable.create { observer in
            CompositionTool.write(images: images, to: path, size: size, duration: duration, fps: fps) {
                
                let url = FilePath.fileURL(subPath: "/test1.mov")
            
                CompositionTool.merge(videoURL: url, audioURL: audioUrl) { fileUrl, error in
                    DispatchQueue.main.async {
                        if let fileUrl = fileUrl {
                            observer.on(.next(fileUrl))
                        } else {
                            observer.on(.error(error!))
                        }
                    }
                }
            }
            
            return Disposables.create {}
        }
        
    }
}
