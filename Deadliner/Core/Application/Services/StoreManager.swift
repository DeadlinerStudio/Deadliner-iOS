//
//  StoreManager.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/12.
//

import StoreKit
import SwiftUI
import Combine

private enum StoreReleaseGate {
    // TODO: Turn this off before shipping the post-Rust public build.
    static let disableInAppPurchaseForCurrentRelease = true
}

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    
    @AppStorage("userTier") private var userTier: UserTier = .free
    
    // 正确的内购 ID
    let geekProductID = "top.aritxonly.deadliner.geek.lifetime"
    
    private var updatesTask: Task<Void, Never>?
    
    private init() {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs = [geekProductID]
            return
        }

        // 启动监听 App Store 外部交易（如在设置中恢复或外部完成）
        updatesTask = Task.detached {
            for await result in StoreKit.Transaction.updates {
                await self.handleTransaction(result: result)
            }
        }
        
        Task {
            await updatePurchasedProducts()
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
        } catch {
            print("❌ StoreKit: 无法拉取商品: \(error)")
        }
    }
    
    /// 发起购买
    func purchase(_ product: Product) async throws -> Bool {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs.insert(geekProductID)
            return true
        }

        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }
    
    /// 恢复购买
    func restorePurchases() async {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs.insert(geekProductID)
            return
        }

        try? await AppStore.sync()
        await updatePurchasedProducts()
    }
    
    /// 检查并同步内购权限到 AppStorage
    func updatePurchasedProducts() async {
        if StoreReleaseGate.disableInAppPurchaseForCurrentRelease {
            userTier = .geek
            purchasedProductIDs = [geekProductID]
            return
        }

        var purchasedIDs = Set<String>()
        
        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchasedIDs.insert(transaction.productID)
            }
        }
        
        self.purchasedProductIDs = purchasedIDs
        
        // 如果拥有 Geek 永久版权限，更新 UserTier
        if purchasedIDs.contains(geekProductID) {
            userTier = .geek
        }
    }
    
    private func handleTransaction(result: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await updatePurchasedProducts()
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
}
