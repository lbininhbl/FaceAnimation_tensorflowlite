//
//  MainViewModel.swift
//  FaceAnimation_tensorflowlite
//
//  Created by zhangerbing on 2021/9/27.
//

import Foundation
import RxSwift
import RxRelay

class MainViewModel {
    // MARK: - Inputs
    let image: BehaviorSubject<UIImage>
    
    let execute: PublishSubject<String>
    
    // MARK: - Outputs
    let list: Observable<[String]>
    
    let video: Observable<URL>
    
    private let bag = DisposeBag()
    
    init(faceAnimation: FaceAnimation = FaceAnimation()) {
        // 初始化图片
        let imagePath = Bundle.main.path(forResource: "ctf", ofType: "jpg")!
        let testImage = UIImage(contentsOfFile: imagePath)!
        image = BehaviorSubject<UIImage>(value: testImage)
        
        // 初始化列表
        self.list = Observable<[String]>.just(["开始执行", "保存到相册", "重播"])
        
        self.execute = PublishSubject<String>()
    
        self.video = Observable.combineLatest(execute, image)
            .filter { $0.0 == "开始执行" }
            .flatMap { faceAnimation.execute(image: $0.1) }
        
    }
}
