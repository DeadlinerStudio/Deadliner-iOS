//
//  ImageCropper.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/12.
//

import SwiftUI

struct ImageCropper: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage
    var onCrop: (UIImage) -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let cropFrameSize: CGFloat = 300
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // 背景图层：显示原始图片，支持缩放和位移
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                
                // 遮罩层：突出显示圆形裁剪区域
                Color.black.opacity(0.5)
                    .mask(
                        ZStack {
                            Rectangle()
                            Circle()
                                .frame(width: cropFrameSize, height: cropFrameSize)
                                .blendMode(.destinationOut)
                        }
                    )
                    .allowsHitTesting(false)
                
                // 裁剪边框
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropFrameSize, height: cropFrameSize)
                    .allowsHitTesting(false)
            }
            .navigationTitle("裁剪头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        cropAndFinish()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private func cropAndFinish() {
        let screenSize = UIScreen.main.bounds.size
        let renderer = ImageRenderer(content: 
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(width: screenSize.width, height: screenSize.height)
        )
        
        renderer.scale = UIScreen.main.scale
        
        if let fullImage = renderer.uiImage {
            let scale = fullImage.scale
            let cropRect = CGRect(
                x: (screenSize.width - cropFrameSize) / 2 * scale,
                y: (screenSize.height - cropFrameSize) / 2 * scale,
                width: cropFrameSize * scale,
                height: cropFrameSize * scale
            )
            
            if let cgImage = fullImage.cgImage?.cropping(to: cropRect) {
                let croppedUIImage = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
                onCrop(croppedUIImage)
                dismiss()
            }
        }
    }
}

extension View {
    @MainActor
    func snapshot() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        return renderer.uiImage
    }
}
