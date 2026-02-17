import Foundation

public struct AppSubscription: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var description: String?
    public var price: Double
    public var currency: String = "USD"
    public var billingCycle: BillingCycle
    public var nextDueDate: Date
    public var isActive: Bool = true
    public var iconName: String?

    public init(id: UUID = UUID(), name: String, description: String? = nil, price: Double, currency: String = "USD", billingCycle: BillingCycle, nextDueDate: Date, isActive: Bool = true, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.currency = currency
        self.billingCycle = billingCycle
        self.nextDueDate = nextDueDate
        self.isActive = isActive
        self.iconName = iconName
    }

    // Alias for compatibility with new UI code which uses 'billingPeriod'
    public var billingPeriod: BillingCycle {
        get { return billingCycle }
        set { billingCycle = newValue }
    }
}

public enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, yearly
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

public extension AppSubscription {
    /// Monthly equivalent of this subscription's price.
    /// - weekly: price * 52 / 12
    /// - monthly: price
    /// - yearly: price / 12
    var monthlyAmount: Double {
        let base = max(0.0, price)
        switch billingCycle {
        case .monthly:
            return base
        case .yearly:
            return base / 12.0
        case .weekly:
            return (base * 52.0) / 12.0
        }
    }

    /// Yearly equivalent of this subscription's price.
    /// - monthly: price * 12
    /// - yearly: price
    /// - weekly: price * 52
    var yearlyAmount: Double {
        let base = max(0.0, price)
        switch billingCycle {
        case .monthly:
            return base * 12.0
        case .yearly:
            return base
        case .weekly:
            return base * 52.0
        }
    }
}
