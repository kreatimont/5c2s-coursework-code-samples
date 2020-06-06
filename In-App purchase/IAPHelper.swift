//
//  IAPHelper.swift
//  CityTransportGuide
//
//  Created by Alexandr Nadtoka on 4/29/19.
//  Copyright © 2019 kreatimont. All rights reserved.
//

import StoreKit
import CocoaLumberjackSwift

public typealias ProductIdentifier = String
public typealias ProductsRequestCompletionHandler = (_ success: Bool, _ products: [SKProduct]?) -> ()

class IAPHelper: NSObject {

    private let productIndentifiers: Set<ProductIdentifier>
    
    private var purchasedProductIdentifiers: Set<ProductIdentifier> = []
    private var productRequest: SKProductsRequest?
    private var productRequestCompletionHandler: ProductsRequestCompletionHandler?
    
    init(productIDs: Set<ProductIdentifier>) {
        self.productIndentifiers = productIDs
        for productId in productIDs {
            let purchased = UserDefaults.standard.bool(forKey: productId)
            if purchased {
                purchasedProductIdentifiers.insert(productId)
                DDLogInfo("[IAPHelper💸] Previously purchased: \(productId)")
            } else {
                DDLogInfo("[IAPHelper💸] Not purchased: \(productId)")
            }
        }
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    func requestProducts(completionHandler: @escaping ProductsRequestCompletionHandler) {
        productRequest?.cancel()
        productRequestCompletionHandler = completionHandler
        
        productRequest = SKProductsRequest(productIdentifiers: productIndentifiers)
        productRequest?.delegate = self
        productRequest?.start()
    }
    
    func isProductPurchased(_ productIdentifier: ProductIdentifier) -> Bool {
        return self.purchasedProductIdentifiers.contains(productIdentifier)
    }
    
    func buyProduct(_ product: SKProduct) {
        DDLogInfo("[IAPHelper💸] Buying \(product.productIdentifier)...")
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
}

extension IAPHelper: SKProductsRequestDelegate {
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        let products = response.products
        productRequestCompletionHandler?(true, products)
        clearRequestAndHandler()
        
        for p in products {
            DDLogInfo("[IAPHelper💸] Found product: \(p.productIdentifier) \(p.localizedTitle) \(p.price.floatValue)")
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        productRequestCompletionHandler?(false, nil)
        clearRequestAndHandler()
        DDLogInfo("[IAPHelper💸] Failed to load list of products.")
        DDLogInfo("[IAPHelper💸] Error: \(error.localizedDescription)")
    }
    
    func clearRequestAndHandler() {
        productRequest = nil
        productRequestCompletionHandler = nil
    }
    
    func restorePurchase() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    static func canMakePayments() -> Bool {
        return SKPaymentQueue.canMakePayments()
    }
    
}

extension IAPHelper: SKPaymentTransactionObserver {
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                complete(transaction: transaction)
                break
            case .failed:
                fail(transaction: transaction)
                break
            case .restored:
                restore(transaction: transaction)
                break
            case .deferred:
                break
            case .purchasing:
                break
            @unknown default:
                DDLogInfo("[IAPHelper💸] Unknow state of transaction: \(transaction)")
            }
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        DDLogInfo("[IAPHelper💸]  fail restore transaction...\n\(error.localizedDescription)")
        NotificationCenter.default.post(name: .IAPHelperPurchaseNotificationFail, object: Constants.removeAdsInApp)
    }
    
    private func complete(transaction: SKPaymentTransaction) {
        DDLogInfo("[IAPHelper💸] complete...")
        deliverPurchaseNotificationFor(identifier: transaction.payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func restore(transaction: SKPaymentTransaction) {
        guard let productIdentifier = transaction.original?.payment.productIdentifier else { return }
        
        DDLogInfo("[IAPHelper💸]  restore... \(productIdentifier)")
        deliverPurchaseNotificationFor(identifier: productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func fail(transaction: SKPaymentTransaction) {
        DDLogInfo("[IAPHelper💸]  fail...")
        if let transactionError = transaction.error as NSError?,
            let localizedDescription = transaction.error?.localizedDescription,
            transactionError.code != SKError.paymentCancelled.rawValue {
            DDLogInfo("[IAPHelper💸]  Transaction Error: \(localizedDescription)")
        }
        
        SKPaymentQueue.default().finishTransaction(transaction)
        
        NotificationCenter.default.post(name: .IAPHelperPurchaseNotificationFail, object: transaction.payment.productIdentifier)
    }
    
    private func deliverPurchaseNotificationFor(identifier: String?) {
        guard let identifier = identifier else { return }
        
        purchasedProductIdentifiers.insert(identifier)
        UserDefaults.standard.set(true, forKey: identifier)
        NotificationCenter.default.post(name: .IAPHelperPurchaseNotification, object: identifier)
    }
    
}



