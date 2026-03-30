//
//  AddHabitSheet.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/7.
//

import SwiftUI

struct AddHabitSheetView: View {
    var onDone: (() -> Void)? = nil
    var principalToolbarContent: AnyView? = nil
    var embedsInParentNavigationStack: Bool = false
    var saveTrigger: Int = 0
    var onSaveEnabledChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        HabitEditorSheetView(
            mode: .add,
            onDone: onDone,
            principalToolbarContent: principalToolbarContent,
            embedsInParentNavigationStack: embedsInParentNavigationStack,
            saveTrigger: saveTrigger,
            onSaveEnabledChange: onSaveEnabledChange
        )
    }
}
