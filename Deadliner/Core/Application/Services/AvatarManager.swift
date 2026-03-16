//
//  AvatarManager.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/12.
//

import SwiftUI
import PhotosUI
import Combine

@MainActor
final class AvatarManager: ObservableObject {
    static let shared = AvatarManager()
    
    @Published var avatarImage: Image?
    @AppStorage("hasCustomAvatar") private var hasCustomAvatar = false
    
    private let avatarFileName = "user_avatar.jpg"
    
    private init() {
        loadAvatar()
    }
    
    func loadAvatar() {
        guard hasCustomAvatar else { return }
        
        let url = getAvatarURL()
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            self.avatarImage = Image(uiImage: uiImage)
        }
    }
    
    func saveAvatar(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }
        
        saveAvatar(uiImage: uiImage)
    }
    
    func saveAvatar(uiImage: UIImage) {
        // 压缩并保存
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
            let url = getAvatarURL()
            try? jpegData.write(to: url)
            self.hasCustomAvatar = true
            self.avatarImage = Image(uiImage: uiImage)
            
            // 发送通知通知其他界面更新
            NotificationCenter.default.post(name: .ddlAvatarChanged, object: nil)
        }
    }
    
    func removeAvatar() {
        let url = getAvatarURL()
        try? FileManager.default.removeItem(at: url)
        self.hasCustomAvatar = false
        self.avatarImage = nil
        NotificationCenter.default.post(name: .ddlAvatarChanged, object: nil)
    }
    
    private func getAvatarURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(avatarFileName)
    }
}

extension NSNotification.Name {
    static let ddlAvatarChanged = NSNotification.Name("ddlAvatarChanged")
}
