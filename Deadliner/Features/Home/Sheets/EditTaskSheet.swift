//
//  EditTaskSheet.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/1.
//

import SwiftUI

struct EditTaskSheetView: View {
    let repository: TaskRepository
    let item: DDLItem
    var onDone: (() -> Void)? = nil

    var body: some View {
        TaskEditorSheetView(
            repository: repository,
            mode: .edit(original: item),
            initialDraft: .fromDDL(item),
            onDone: onDone
        )
    }
}
