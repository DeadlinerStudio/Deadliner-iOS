//
//  UserTier.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

enum UserTier: String {
    case free = "free"
    case geek = "geek"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .free: return "FREE 用户"
        case .geek: return "GEEK 极客"
        case .pro: return "GEEK 极客"
        }
    }
}
