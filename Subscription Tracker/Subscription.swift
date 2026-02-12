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
