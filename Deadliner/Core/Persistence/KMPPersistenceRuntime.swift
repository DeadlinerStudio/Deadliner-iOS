//
//  KMPPersistenceRuntime.swift
//  Deadliner
//
//  Owns the KMP database for the lifetime of the iOS process.
//

#if canImport(Shared)
import Shared

actor KMPPersistenceRuntime {
    static let shared = KMPPersistenceRuntime()

    private let database: DeadlinerDatabase
    private let notificationServiceInstance: NotificationService
    private let notificationOrchestratorInstance: NotificationOrchestrator
    private let categoryStoreInstance: KMPTaskCategoryStore
    private let taskStoreInstance: KMPTaskStore
    private let habitStoreInstance: KMPHabitStore
    private let captureStoreInstance: KMPCaptureStore
    private let memoryStoreInstance: KMPMemoryStore
    private let focusAlarmPortInstance: FocusAlarmPortAdapter

    private init() {
        AppLog.event(
            "kmp.runtime.open",
            domain: .kmp,
            context: ["database": KMPSharedDatabaseLocation.databaseName]
        )
        let database = DeadlinerDatabase.companion.create(
            factory: IosDatabaseDriverFactory(databasePath: KMPSharedDatabaseLocation.databasePath)
        )
        let notificationService = NotificationService()
        let focusAlarmPort = FocusAlarmPortAdapter.shared
        self.database = database
        notificationServiceInstance = notificationService
        notificationOrchestratorInstance = database.createNotificationOrchestrator(
            notificationService: notificationService
        )
        categoryStoreInstance = KMPTaskCategoryStore(database: database)
        taskStoreInstance = KMPTaskStore(database: database)
        habitStoreInstance = KMPHabitStore(database: database)
        captureStoreInstance = KMPCaptureStore(database: database)
        memoryStoreInstance = KMPMemoryStore(database: database)
        focusAlarmPortInstance = focusAlarmPort
    }

    func categoryStore() -> KMPTaskCategoryStore {
        categoryStoreInstance
    }

    func taskStore() -> KMPTaskStore {
        taskStoreInstance
    }

    func coreDatabase() -> DeadlinerDatabase {
        database
    }

    /// Shared notification lifecycle authority. Existing KMP projection stores
    /// continue to use the native schedulers until the platform actual can
    /// preserve their precise due-date and calendar semantics.
    func notificationOrchestrator() -> NotificationOrchestrator {
        notificationOrchestratorInstance
    }

    func taskListStateBridge() -> IosTaskListStateBridge {
        IosTaskListStateBridge(
            taskRepository: database.tasks,
            notificationOrchestrator: notificationOrchestratorInstance
        )
    }

    func habitListStateBridge() -> IosHabitListStateBridge {
        IosHabitListStateBridge(
            habitRepository: database.habits,
            notificationOrchestrator: notificationOrchestratorInstance
        )
    }

    /// Creates the Overview bridge next to the database it observes. Keeping
    /// this construction inside the runtime prevents a foreign KMP database
    /// object from crossing an additional Swift actor boundary during tab
    /// creation.
    func overviewStateBridge() -> IosOverviewStateBridge {
        IosOverviewStateBridge(database: database)
    }

    func focusTimerStateBridge() -> IosFocusTimerStateBridge {
        IosFocusTimerStateBridge(database: database, alarmPort: focusAlarmPortInstance)
    }

    func isAvailableFocusSession(uid: String) -> Bool {
        guard let session = database.focusSessions.find(uid: uid) else { return false }
        return !session.isDeleted
    }

    func mutateHabitIfFocusResolved(uid: String, delete: Bool) async -> FocusTimerOutcome {
        let bridge = IosFocusTimerStateBridge(database: database)
        let outcome = await withCheckedContinuation { continuation in
            bridge.mutateHabitIfFocusResolved(habitUid: uid, delete: delete) { value in continuation.resume(returning: value) }
        }
        bridge.close()
        return outcome
    }

    func habitStore() -> KMPHabitStore {
        habitStoreInstance
    }

    func captureStore() -> KMPCaptureStore {
        captureStoreInstance
    }

    func memoryStore() -> KMPMemoryStore {
        memoryStoreInstance
    }

    func close() {
        AppLog.event("kmp.runtime.close", domain: .kmp)
        database.close()
    }
}
#endif
