import Foundation

/// Stable storage keys shared with Android and HarmonyOS; cloud AI configuration is separate.
enum QuickAddBackend: String, CaseIterable, Identifiable {
    case kivo, rules, original
    static let settingKey = "quick_add_backend"
    var id: String { rawValue }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: settingKey) ?? "") ?? .kivo }

    var title: String {
        switch self {
        case .kivo: return "Kivo（默认）"
        case .rules: return "规则识别"
        case .original: return "原版端侧模型"
        }
    }
    var description: String {
        switch self {
        case .kivo: return "Kivo 在设备上识别标题、时间、地点和习惯安排，首次使用需下载模型。当前支持中文，英文界面使用原版英文模型。下次打开快速添加时生效。"
        case .rules: return "使用内置规则识别，不下载或加载模型。下次打开快速添加时生效。"
        case .original: return "使用此前的端侧识别模型，按界面语言下载。下次打开快速添加时生效。"
        }
    }
    func manifestResource(language: String) -> String? {
        if self == .rules { return nil }
        if language.lowercased().hasPrefix("en") { return "quick-add-model-en" }
        return self == .kivo ? "quick-add-model-kivo-preview" : "quick-add-model"
    }
    func modelName(language: String) -> String {
        manifestResource(language: language) == "quick-add-model-kivo-preview" ? "Kivo" : "端侧模型"
    }
}
