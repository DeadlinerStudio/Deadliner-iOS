import BackgroundTasks
import Foundation
import Network
#if canImport(Shared)
import Shared
#endif

/// OS integration only: timing, retries and coalescing are implemented in KMP.
final class SyncBackgroundDriver {
    static let identifier = "com.deadliner.sync"
    private static let lock = NSLock()
    private static var monitor: NWPathMonitor?
    private static var settingsObserver: NSObjectProtocol?

    static func register() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: LocalValues.syncConfigurationDidChange, object: nil, queue: nil
        ) { _ in
            _Concurrency.Task { await SyncCoordinator.shared.configureAutomaticSync() }
        }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let run = BackgroundSyncRun(task: task)
            run.start()
        }
        if !registered { AppLog.event("sync.background.registration-failed", domain: .sync, level: .error) }
    }

    static func schedule(enabled: Bool) {
        guard enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { AppLog.event("sync.background.schedule-failed", domain: .sync, level: .warning) }
    }

    static func startNetworkObservation() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }
        let observer = NWPathMonitor()
        observer.pathUpdateHandler = { path in
            _Concurrency.Task { await SyncCoordinator.shared.setNetworkAvailable(path.status == .satisfied) }
        }
        monitor = observer
        observer.start(queue: DispatchQueue(label: "deadliner.sync.network"))
    }
}

/// Explicit Kotlin handle bridges OS expiration to coroutine cancellation.
private final class BackgroundSyncRun: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var completed = false
    #if canImport(Shared)
    private var request: SyncRequest?
    #endif
    private var preparation: _Concurrency.Task<Void, Never>?

    init(task: BGTask) { self.task = task }

    func start() {
        task.expirationHandler = { [self] in finish(success: false) }
        let preparation = _Concurrency.Task { [self] in
            #if canImport(Shared)
            // App.init prepared the persistent database location before launch completed.
            // A refresh does not need to initialize the AI runtime or load its models.
            await SyncCoordinator.shared.configureAutomaticSync()
            let database = await KMPPersistenceRuntime.shared.coreDatabase()
            begin(database: database)
            #else
            finish(success: false)
            #endif
        }
        lock.lock()
        if completed { preparation.cancel() } else { self.preparation = preparation }
        lock.unlock()
    }

    #if canImport(Shared)
    private func begin(database: DeadlinerDatabase) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        request = database.startSync(trigger: .background) { [self] outcome in
            _Concurrency.Task {
                await SyncCoordinator.shared.finishBackgroundSync(outcome)
                finish(success: outcome.succeeded)
            }
        }
    }
    #endif

    private func finish(success: Bool) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let preparation = self.preparation
        self.preparation = nil
        #if canImport(Shared)
        let request = self.request
        self.request = nil
        #endif
        lock.unlock()
        if !success {
            preparation?.cancel()
            #if canImport(Shared)
            request?.cancel()
            #endif
        }
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        // configureAutomaticSync scheduled the successor after reading current settings.
    }
}
