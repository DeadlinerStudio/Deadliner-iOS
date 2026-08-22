//
//  KMPHabitListViewModelBridge.swift
//  Deadliner
//
//  MainActor bridge from the shared HabitListViewModel StateFlow to SwiftUI.
//

#if canImport(Shared)
import Shared

@MainActor
final class KMPHabitListViewModelBridge {
    private let bridge: IosHabitListStateBridge

    private init(bridge: IosHabitListStateBridge) {
        self.bridge = bridge
    }

    static func make() async -> KMPHabitListViewModelBridge {
        let bridge = await KMPPersistenceRuntime.shared.habitListStateBridge()
        return KMPHabitListViewModelBridge(bridge: bridge)
    }

    func start(onState: @escaping @MainActor (HabitListUiState) -> Void) {
        bridge.start(onState: { state in
            onState(state)
        })
    }

    func refresh() {
        bridge.refresh()
    }

    func selectDate(_ rawDate: String) {
        bridge.selectDate(rawDate: rawDate)
    }

    func applyPrimaryAction(habitUID: String) {
        bridge.applyPrimaryAction(habitUid: habitUID)
    }

    deinit {
        bridge.close()
    }
}
#endif
