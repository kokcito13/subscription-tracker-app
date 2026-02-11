import Foundation

struct Subscription: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var billingCycle: BillingCycle
    var nextDueDate: Date
    var isActive: Bool = true

    static func sampleData() -> [Subscription] {
        [
            Subscription(name: "Spotify", price: 9.99, billingCycle: .monthly, nextDueDate: Date().addingTimeInterval(60*60*24*10)),
            Subscription(name: "iCloud+", price: 0.99, billingCycle: .monthly, nextDueDate: Date().addingTimeInterval(60*60*24*5)),
            Subscription(name: "Netflix", price: 13.99, billingCycle: .monthly, nextDueDate: Date().addingTimeInterval(60*60*24*20))
        ]
    }
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
