//
//  StoreManager.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/12.
//

import StoreKit
import SwiftUI
import Combine
import os

private enum StoreReleaseGate {
    // TODO: Turn this off before shipping the post-Rust public build.
    static let disableInAppPurchaseForCurrentRelease = false
}

@MainActor
final class StoreManager: ObservableObject {
    private enum EntitlementRefreshReason {
        case passive
        case postSync
    }

    static let shared = StoreManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    
    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("store.has_geek_entitlement_cache") private var hasGeekEntitlementCache: Bool = false
    
    let geekProductID = "top.aritxonly.deadliner.geek.lifetime"
    private let launchSyncCooldown: TimeInterval = 60 * 60 * 6
    private let launchSyncTimeoutSeconds: Double = 3.0
    private let lastLaunchSyncAtKey = "store.launch.last_sync_at"
    
    private var updatesTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "Deadliner", category: "StoreManager")

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        SyncDebugLog.log("[StoreKit] \(message)")
    }
    
    private init() {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs = [geekProductID]
            log("release gate enabled, force unlock geek tier")
            return
        }

        // 启动监听 App Store 外部交易（如在设置中恢复或外部完成）
        updatesTask = Task.detached {
            for await result in StoreKit.Transaction.updates {
                await self.handleTransaction(result: result)
            }
        }
        
        Task {
            await updatePurchasedProducts(reason: .passive)
            await fetchProducts()
        }
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    /// 从 App Store 拉取商品信息
    func fetchProducts() async {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            products = []
            return
        }

        do {
            let storeProducts = try await Product.products(for: [geekProductID])
            self.products = storeProducts
            log("fetched products: \(storeProducts.map(\.id).joined(separator: ", "))")
        } catch {
            log("failed to fetch products: \(error.localizedDescription)")
        }
    }
    
    /// 发起购买
    func purchase(_ product: Product) async throws -> Bool {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs.insert(geekProductID)
            log("purchase bypassed by release gate for product: \(product.id)")
            return true
        }

        log("start purchase for product: \(product.id)")
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            log("purchase success for product: \(transaction.productID)")
            await updatePurchasedProducts(reason: .passive)
            await transaction.finish()
            return true
        case .userCancelled:
            log("purchase cancelled by user for product: \(product.id)")
            return false
        case .pending:
            log("purchase pending for product: \(product.id)")
            return false
        @unknown default:
            log("purchase returned unknown result for product: \(product.id)")
            return false
        }
    }
    
    /// 恢复购买
    func restorePurchases() async {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs.insert(geekProductID)
            log("restore bypassed by release gate")
            return
        }

        log("start restore purchases")
        try? await AppStore.sync()
        await updatePurchasedProducts(reason: .postSync)
    }

    /// App 启动/回前台时调用：
    /// 1) 先本地 entitlement 快速同步，保证弱网也能立即更新 UI
    /// 2) 再后台做一次限时网络校验，超时即放弃，不影响交互
    func refreshEntitlementsOnLaunch() async {
        await updatePurchasedProducts(reason: .passive)

        Task { [weak self] in
            guard let self else { return }
            guard self.shouldRunLaunchSyncNow else {
                self.log("skip launch sync due to cooldown")
                return
            }

            self.markLaunchSyncAttempt()
            let synced = await self.syncAppStoreWithTimeout(seconds: self.launchSyncTimeoutSeconds)
            if synced {
                self.log("launch sync completed")
                await self.updatePurchasedProducts(reason: .postSync)
            } else {
                self.log("launch sync skipped/timeout/failure, keep local entitlement state")
            }
        }
    }
    
    /// 检查并同步内购权限到 AppStorage
    func updatePurchasedProducts() async {
        await updatePurchasedProducts(reason: .passive)
    }

    private func updatePurchasedProducts(reason: EntitlementRefreshReason) async {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs = [geekProductID]
            hasGeekEntitlementCache = true
            return
        }

        var purchasedIDs = Set<String>()
        
        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchasedIDs.insert(transaction.productID)
            }
        }
        
        self.purchasedProductIDs = purchasedIDs
        
        // 稳定性策略：
        // - 读取到有效权益时，立即升级并缓存
        // - 读取为空时，只有 postSync（成功 AppStore.sync 之后）才允许降级
        //   被动刷新（启动/回前台/监听）不做降级，避免弱网或临时抖动导致误判
        if purchasedIDs.contains(geekProductID) {
            userTier = .geek
            hasGeekEntitlementCache = true
        } else {
            switch reason {
            case .postSync:
                userTier = .free
                hasGeekEntitlementCache = false
            case .passive:
                if !hasGeekEntitlementCache {
                    userTier = .free
                }
            }
        }
        let entitlements = purchasedIDs.sorted().joined(separator: ", ")
        log("current entitlements: [\(entitlements)] reason=\(String(describing: reason)) cache=\(hasGeekEntitlementCache) => userTier=\(userTier.rawValue)")
    }
    
    private func handleTransaction(result: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        log("transaction update received for product: \(transaction.productID)")
        await updatePurchasedProducts(reason: .passive)
        await transaction.finish()
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private var shouldRunLaunchSyncNow: Bool {
        let last = UserDefaults.standard.double(forKey: lastLaunchSyncAtKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= launchSyncCooldown
    }

    private func markLaunchSyncAttempt() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastLaunchSyncAtKey)
    }

    private func syncAppStoreWithTimeout(seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await AppStore.sync()
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                let ns = UInt64(max(0.1, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
