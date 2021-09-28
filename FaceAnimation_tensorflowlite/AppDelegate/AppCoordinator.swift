//
//  AppCoordinator.swift
//  FaceAnimation_tensorflowlite
//
//  Created by zhangerbing on 2021/9/27.
//

import Foundation
import RxSwift

class AppCoordinator: BaseCoordinator<Void> {
    private let window: UIWindow
    
    init(window: UIWindow) {
        self.window = window
    }
    
    override func start() -> Observable<Void> {
        let mainCoordinator = MainCoordinator(window: window)
        return coordinate(to: mainCoordinator)
    }
}
