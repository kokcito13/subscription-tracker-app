import Foundation

struct Subscription: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var billingCycle: BillingCycle
    var nextDueDate: Date
    var isActive: Bool = true
}

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, yearly
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

extension Subscription {
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
