//
//  Generator.swift
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/20.
//

import Foundation
import TensorFlowLite
import TensorFlowLiteCMetal
import TensorFlowLiteCCoreML

class Generator: ModelDataHandler {
    var normalizeRange: NormalizeRange = .zero_to_one
    
    let inputWidth: Int = 0
    
    let inputHeight: Int = 0
    
    var interpreter: Interpreter
    
    required init?(model: TFLiteModel, threadCount: Int = 1) {
        let modelFileName = model.name
        let fileExtension = model.extension
        
        // 加载模型文件
        guard let modelPath = Bundle.main.path(forResource: modelFileName, ofType: fileExtension) else { return nil }
        
        var options = Interpreter.Options()
        options.threadCount = threadCount
        
        do {
            var option = CoreMLDelegate.Options()
            option.enabledDevices = .all
            option.coreMLVersion = 3
            var delegate: Delegate? = CoreMLDelegate(options: option)
            
            if delegate == nil {
                delegate = MetalDelegate()
            }
            // 创建解析器
//            interpreter = try Interpreter(modelPath: modelPath, options: options, delegates: [delegate!])
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter.allocateTensors()
            
            let ten1 = try interpreter.input(at: 0)
            let ten2 = try interpreter.input(at: 1)
            let ten3 = try interpreter.input(at: 2)
            let ten4 = try interpreter.input(at: 3)
            let ten5 = try interpreter.input(at: 4)
            [ten1, ten2, ten3, ten4, ten5].forEach { print($0.name) }
            
            print("")
            
        } catch {
            let error = error as NSError
            print("创建解析器失败:", error.localizedDescription)
            return nil
        }
        
        print("\(modelFileName)创建成功，输入:\(interpreter.inputTensorCount)个, 输出:\(interpreter.outputTensorCount)个")
    }
    
    // MARK: - 运行模型
    func runModelFlat(onFrame pixelBuffer: CVPixelBuffer, values: [Float], jacobian: [Float], kp_value: [Float], kp_jacobian: [Float]) -> Any? {
        
        let kp_driving = values.withUnsafeBufferPointer(Data.init)
        let kp_driving_jacobian = jacobian.withUnsafeBufferPointer(Data.init)
        
        let kp_source = kp_value.withUnsafeBufferPointer(Data.init)
        let kp_source_jacobian = kp_jacobian.withUnsafeBufferPointer(Data.init)
        
        let width = CVPixelBufferGetWidth(pixelBuffer);
        let height = CVPixelBufferGetHeight(pixelBuffer);
        guard let source_image = rgbDataFromBuffer(pixelBuffer, byteCount: width * height * inputchannels) else {
            print("图像转换成RGB数据失败")
            return nil
        }
        
        let params: [String: Data] = [
            "serving_default_source_image:0": source_image,
            "serving_default_kp_source_jacobian:0": kp_source_jacobian,
            "serving_default_kp_source:0": kp_source,
            "serving_default_kp_driving_jacobian:0": kp_driving_jacobian,
            "serving_default_kp_driving:0": kp_driving
        ]
        
        let outputTensor1: Tensor
        
        do {
            
            for i in 0..<interpreter.inputTensorCount {
                let ten = try interpreter.input(at: i)
                try interpreter.copy(params[ten.name]!, toInputAt: i)
            }
            
            // 执行解析器
            try interpreter.invoke()
            
            outputTensor1 = try interpreter.output(at: 0) // 是图像 [256, 256, 3]
            
        } catch let error {
            print("执行解析器失败: ", error.localizedDescription)
            return nil
        }
        
        // 处理结果数据
        let result1 = [Float](unsafeData: outputTensor1.data) ?? []
        
        let result = handleResult(result: result1)
        return result
    }
    
    private func handleResult(result: [Float]) -> ([[[Float]]]) {
        var image = [[[Float]]]()
        
        let rows = 256
        let cols = 256
        let cs = 3
        
        autoreleasepool {
            for i in 0..<rows {
                autoreleasepool {
                    var temp = [[Float]]()
                    for j in 0..<cols {
                        autoreleasepool {
                            var temp2 = [Float]()
                            for k in 0..<cs {
                                let index = i * cols * cs + j * cs + k;
                                let data = result[index]
                                temp2.append(data)
                            }
                            temp.append(temp2)
                        }
                    }
                    image.append(temp)
                }
            }
        }
        
        return image
    }
}
