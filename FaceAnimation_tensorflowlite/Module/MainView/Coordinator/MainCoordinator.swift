//
//  MainCoordinator.swift
//  FaceAnimation_tensorflowlite
//
//  Created by zhangerbing on 2021/9/27.
//

import Foundation
import RxSwift

class MainCoordinator: BaseCoordinator<Void> {
    private let window: UIWindow
    
    private let bag = DisposeBag()
    
    init(window: UIWindow) {
        self.window = window
    }
    
    override func start() -> Observable<Void> {
        let vc = MainViewController.initFromStoryboard()
        let navc = UINavigationController(rootViewController: vc)
        navc.isNavigationBarHidden = true
        
        let viewModel = MainViewModel(faceAnimation: FaceAnimation())
        vc.viewModel = viewModel
        
        window.rootViewController = navc
        window.makeKeyAndVisible()
        
        return .never()
    }
}
