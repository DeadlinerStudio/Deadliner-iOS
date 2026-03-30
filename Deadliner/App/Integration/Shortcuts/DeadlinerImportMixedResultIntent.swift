//
//  DeadlinerImportMixedResultIntent.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/28.
//

import AppIntents
import Foundation

struct DeadlinerImportMixedResultIntent: AppIntent {
    static var title: LocalizedStringResource = "Deadliner 导入 JSON"
    static var description = IntentDescription("导入 MixedResult JSON 并创建任务。")

    @Parameter(title: "JSON 文本")
    var jsonText: String

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let container = SharedModelContainer.shared
            try await TaskRepository.shared.initializeIfNeeded(container: container)
            
            let data = Data(jsonText.utf8)
            let mixed = try JSONDecoder().decode(MixedResult.self, from: data)

            let useCase = ImportMixedResultUseCase(taskWriter: TaskRepository.shared)
            let stats = try await useCase.execute(mixed)

            return .result(dialog: "导入完成：任务 \(stats.tasksInserted) 条。")
        } catch {
            return .result(dialog: "导入失败：\(error.localizedDescription)")
        }
    }
}
