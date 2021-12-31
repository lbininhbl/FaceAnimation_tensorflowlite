//
//  KPProcessor.swift
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/20.
//

import Foundation
import TensorFlowLite

class KPProcessor: ModelDataHandler {
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
            option.enabledDevices = .neuralEngine
            option.coreMLVersion = 3
            var delegate: Delegate? = CoreMLDelegate(options: option)
            
            if delegate == nil {
                delegate = MetalDelegate()
            }
            // 创建解析器
//            interpreter = try Interpreter(modelPath: modelPath, options: options, delegates: [delegate!])
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter.allocateTensors()
        } catch {
            let error = error as NSError
            print("创建解析器失败:", error.localizedDescription)
            return nil
        }
        
        print("\(modelFileName)创建成功，输入:\(interpreter.inputTensorCount)个, 输出:\(interpreter.outputTensorCount)个")
    }
    
    // MARK: - 运行模型
    func runModelFlat(with values: [Float], jacobian: [Float], init_value: [Float], init_jacobian: [Float], kp_value: [Float], kp_jacobian: [Float]) -> Any? {
        
        // kp_driving_initial_jacobian
        let kp_driving_initial_jacobian = init_jacobian.withUnsafeBufferPointer(Data.init)
        // kp_driving
        let kp_driving = values.withUnsafeBufferPointer(Data.init)
        // kp_source_jacobian
        let kp_source_jacobian = kp_jacobian.withUnsafeBufferPointer(Data.init)
        // kp_source
        let kp_source = kp_value.withUnsafeBufferPointer(Data.init)
        // kp_driving_jacobian
        let kp_driving_jacobian = jacobian.withUnsafeBufferPointer(Data.init)
        // kp_driving_initial
        let kp_driving_initial = init_value.withUnsafeBufferPointer(Data.init)
        
        let params: [String: Data] = [
            "serving_default_kp_driving_initial_jacobian:0": kp_driving_initial_jacobian,
            "serving_default_kp_driving:0": kp_driving,
            "serving_default_kp_source_jacobian:0": kp_source_jacobian,
            "serving_default_kp_source:0": kp_source,
            "serving_default_kp_driving_jacobian:0": kp_driving_jacobian,
            "serving_default_kp_driving_initial:0": kp_driving_initial
        ]
        
        let outputTensor1: Tensor
        let outputTensor2: Tensor
        do {
            for i in 0..<interpreter.inputTensorCount {
                let ten = try interpreter.input(at: i)
                try interpreter.copy(params[ten.name]!, toInputAt: i)
            }
            
            // 执行解析器
            try interpreter.invoke()
            
            outputTensor1 = try interpreter.output(at: 1) // 是value [1, 10, 2]
            outputTensor2 = try interpreter.output(at: 0) // 是jacobian [1, 10, 2, 2]
            
        } catch let error {
            print("执行解析器失败: ", error.localizedDescription)
            return nil
        }
        
        // 处理结果数据
        let result1 = [Float](unsafeData: outputTensor1.data) ?? []
        let result2 = [Float](unsafeData: outputTensor2.data) ?? []

        return (values: result1, jacobian: result2)
    }
}
