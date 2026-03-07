//
//  CircularAvatar.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/1.
//

import UIKit

func circularAvatarImage(named name: String, size: CGFloat) -> UIImage? {
    guard let img = UIImage(named: name) else { return nil }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        UIBezierPath(ovalIn: rect).addClip()
        img.draw(in: rect)
    }
}
