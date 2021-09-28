//
//  AssetUtils.swift
//  FaceAnimationTest
//
//  Created by zhangerbing on 2021/8/25.
//

import Foundation
import AVFoundation

struct AssetUtils {
    static func durationOf(fileUrl: URL) -> Double {
        let asset = AVURLAsset(url: fileUrl)
        return asset.duration.seconds
    }
}
