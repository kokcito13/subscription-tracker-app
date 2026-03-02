import Foundation
import Combine

@MainActor
public final class SubscriptionStore: ObservableObject {
    @Published private(set) var subscriptions: [AppSubscription] = []

    private let saveURL: URL
    private var cancellables = Set<AnyCancellable>()

    // When true, changes to `subscriptions` are saved to disk. We temporarily disable
    // persistence when we populate subscriptions from the server (requirement: don't
    // keep server data in local storage).
    private var persistChanges: Bool = true

    // Added: shared currency formatter for presenting totals
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    // Added: computed totals
    var totalMonthly: Double {
        subscriptions.reduce(0.0) { $0 + $1.monthlyAmount }
    }

    var totalYearly: Double {
        subscriptions.reduce(0.0) { $0 + $1.yearlyAmount }
    }

    var totalMonthlyFormatted: String {
        SubscriptionStore.currencyFormatter.string(from: NSNumber(value: totalMonthly)) ?? String(format: "%.2f", totalMonthly)
    }

    var totalYearlyFormatted: String {
        SubscriptionStore.currencyFormatter.string(from: NSNumber(value: totalYearly)) ?? String(format: "%.2f", totalYearly)
    }

    init(filename: String = "subscriptions.json") {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent(filename)

        load()

        // Persist on change (unless persistence is disabled)
        $subscriptions
            .dropFirst()
            .sink { [weak self] subs in
                guard let self = self else { return }
                if self.persistChanges {
                    self.save(subs)
                }
            }
            .store(in: &cancellables)
    }

    func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([AppSubscription].self, from: data)
            self.subscriptions = decoded
        } catch {
            // Previously we populated sample data on first run; remove that so
            // the UI only shows real data fetched from the backend.
            self.subscriptions = []
        }
    }

    func save(_ subs: [AppSubscription]) {
        do {
            let data = try JSONEncoder().encode(subs)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            print("Failed to save subscriptions:\(error)")
        }
    }

    // CRUD
    func add(_ subscription: AppSubscription) {
        subscriptions.append(subscription)
    }

    func update(_ subscription: AppSubscription) {
        guard let idx = subscriptions.firstIndex(of: subscription) else { return }
        subscriptions[idx] = subscription
    }

    func remove(at offsets: IndexSet) {
        // Remove at offsets without relying on SwiftUI's Array extension.
        // Iterate indices in descending order to keep removals valid.
        for index in offsets.sorted(by: >) {
            if subscriptions.indices.contains(index) {
                subscriptions.remove(at: index)
            }
        }
    }

    // Convenience local removal by id
    func remove(_ subscription: AppSubscription) {
        subscriptions.removeAll { $0.id == subscription.id }
    }

    // MARK: - Server sync

    private struct APISubscription: Codable {
        let id: String
        let name: String
        let amount: String
        let currency: String?
        let billingPeriod: String?
        let billingDayOfMonth: Int?
        let billingMonthOfYear: Int?
        let nextBillingDate: String?
        let category: String?
        let status: String?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name, amount, currency, billingPeriod, billingDayOfMonth, billingMonthOfYear, nextBillingDate, category, status, createdAt, updatedAt
        }

        // Memberwise initializer so callers (fallback mapping) can construct instances
        init(id: String, name: String, amount: String, currency: String?, billingPeriod: String?, billingDayOfMonth: Int?, billingMonthOfYear: Int?, nextBillingDate: String?, category: String?, status: String?, createdAt: String?, updatedAt: String?) {
            self.id = id
            self.name = name
            self.amount = amount
            self.currency = currency
            self.billingPeriod = billingPeriod
            self.billingDayOfMonth = billingDayOfMonth
            self.billingMonthOfYear = billingMonthOfYear
            self.nextBillingDate = nextBillingDate
            self.category = category
            self.status = status
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        // Tolerant initializer: `amount` can be a String or a Number in the JSON.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.name = try container.decode(String.self, forKey: .name)

            // amount can be String or Double/Int
            if let aStr = try? container.decode(String.self, forKey: .amount) {
                self.amount = aStr
            } else if let aDouble = try? container.decode(Double.self, forKey: .amount) {
                self.amount = String(format: "%.2f", aDouble)
            } else if let aInt = try? container.decode(Int.self, forKey: .amount) {
                self.amount = String(aInt)
            } else {
                // Default to 0.00 if absent/unexpected
                self.amount = "0.00"
            }

            self.currency = try? container.decodeIfPresent(String.self, forKey: .currency)
            self.billingPeriod = try? container.decodeIfPresent(String.self, forKey: .billingPeriod)
            self.billingDayOfMonth = try? container.decodeIfPresent(Int.self, forKey: .billingDayOfMonth)
            self.billingMonthOfYear = try? container.decodeIfPresent(Int.self, forKey: .billingMonthOfYear)
            self.nextBillingDate = try? container.decodeIfPresent(String.self, forKey: .nextBillingDate)
            self.category = try? container.decodeIfPresent(String.self, forKey: .category)
            self.status = try? container.decodeIfPresent(String.self, forKey: .status)
            self.createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
            self.updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        }
    }

    private static var refreshTask: Task<Void, Error>?
    // Serial queue to atomically create/check the refreshTask
    private static let refreshTaskQueue = DispatchQueue(label: "SubscriptionStore.refreshTaskQueue")

    /// Fetch subscriptions from backend using token obtained from Keychain (with biometric prompt).
    /// This method does not persist the server-provided subscriptions to disk.
    func refreshFromServer() async throws {
        // Avoid performing network/biometric operations while running inside Xcode previews
        // or snapshotting environments which can instantiate views repeatedly.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }

        // Atomically check/create a single-flight task so multiple callers won't create concurrent tasks
        var taskToAwait: Task<Void, Error>!
        SubscriptionStore.refreshTaskQueue.sync {
            if let existing = SubscriptionStore.refreshTask {
                taskToAwait = existing
            } else {
                let newTask = Task { () throws -> Void in
                    // Ensure a token exists first to give a clear error early.
                    guard AuthService.hasTokenInKeychain() else {
                        throw NSError(domain: "SubscriptionStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token found in Keychain"])
                    }

                    // Retrieve token (may show biometric prompt). This occurs inside the task so only the first waiter triggers the prompt.
                    let token = try await AuthService.retrieveToken()

                    // Build URL
                    var url = Config.backendHost
                    url.appendPathComponent("v1")
                    url.appendPathComponent("subscriptions")

                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    let (data, response) = try await URLSession.shared.data(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        let body = String(data: data, encoding: .utf8) ?? "<non-text>"
                        let msg = "Request to \(url.absoluteString) failed with status \(http.statusCode): \(body)"
                        throw NSError(domain: "SubscriptionStore", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                    }

                    // Try decode strict, otherwise fallback map directly to Subscription.
                    let decoder = JSONDecoder()
                    if let apiSubs = try? decoder.decode([APISubscription].self, from: data) {
                        // Map API model to local Subscription
                        let iso = ISO8601DateFormatter()
                        let mapped: [AppSubscription] = apiSubs.map { api in
                            let uuid = UUID(uuidString: api.id) ?? UUID()
                            let price = Double(api.amount) ?? 0.0
                            let bp = (api.billingPeriod ?? "").lowercased()
                            let cycle: BillingCycle
                            switch bp {
                            case "weekly": cycle = .weekly
                            case "yearly", "annually", "annual", "year": cycle = .yearly
                            default: cycle = .monthly
                            }
                            var nextDate = Date()
                            if let nd = api.nextBillingDate {
                                if let d = iso.date(from: nd) { nextDate = d }
                                else {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy-MM-dd"
                                    if let d2 = formatter.date(from: nd) { nextDate = d2 }
                                }
                            }
                            let active = (api.status ?? "").lowercased() == "active"
                            return AppSubscription(id: uuid, name: api.name, price: price, billingCycle: cycle, nextDueDate: nextDate, isActive: active)
                        }

                        await MainActor.run {
                            self.persistChanges = false
                            self.subscriptions = mapped
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.persistChanges = true }
                        }
                        return
                    }

                    // Fallback parsing
                    do {
                        let raw = try JSONSerialization.jsonObject(with: data, options: [])
                        guard let arr = raw as? [[String: Any]] else {
                            throw NSError(domain: "SubscriptionStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
                        }

                        let iso = ISO8601DateFormatter()
                        var mappedFallback: [AppSubscription] = []

                        for dict in arr {
                            let idStr = dict["id"] as? String ?? UUID().uuidString
                            let uuid = UUID(uuidString: idStr) ?? UUID()
                            let name = dict["name"] as? String ?? ""
                            var amountStr = "0.00"
                            if let a = dict["amount"] as? String { amountStr = a }
                            else if let a = dict["amount"] as? Double { amountStr = String(format: "%.2f", a) }
                            else if let a = dict["amount"] as? Int { amountStr = String(a) }
                            let price = Double(amountStr) ?? 0.0
                            let bp = (dict["billingPeriod"] as? String ?? "").lowercased()
                            let cycle: BillingCycle
                            switch bp {
                            case "weekly": cycle = .weekly
                            case "yearly", "annually", "annual", "year": cycle = .yearly
                            default: cycle = .monthly
                            }
                            var nextDate = Date()
                            if let nd = dict["nextBillingDate"] as? String {
                                if let d = iso.date(from: nd) { nextDate = d }
                                else {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy-MM-dd"
                                    if let d2 = formatter.date(from: nd) { nextDate = d2 }
                                }
                            }
                            let active = (dict["status"] as? String ?? "").lowercased() == "active"
                            mappedFallback.append(AppSubscription(id: uuid, name: name, price: price, billingCycle: cycle, nextDueDate: nextDate, isActive: active))
                        }

                        await MainActor.run {
                            self.persistChanges = false
                            self.subscriptions = mappedFallback
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.persistChanges = true }
                        }
                        return
                    } catch let fallbackErr {
                        throw NSError(domain: "SubscriptionStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Decoding failed: \(fallbackErr)"])
                    }
                }
                SubscriptionStore.refreshTask = newTask
                taskToAwait = newTask
            }
        }

        // Await the task outside the lock
        defer {
            SubscriptionStore.refreshTaskQueue.async {
                SubscriptionStore.refreshTask = nil
            }
        }

        return try await taskToAwait.value
    }

    /// Delete a subscription on the server and remove it locally on success.
    func deleteFromServer(_ subscription: AppSubscription) async throws {
        // Avoid performing network/biometric operations while running inside Xcode previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // In previews, just remove locally
            await MainActor.run { self.remove(subscription) }
            return
        }

        // Ensure we have a token in Keychain first
        guard AuthService.hasTokenInKeychain() else {
            throw NSError(domain: "SubscriptionStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token found in Keychain"])
        }

        // Retrieve token (may prompt biometric)
        let token = try await AuthService.retrieveToken()

        // Build URL: DELETE /v1/subscriptions/{id}
        var url = Config.backendHost
        url.appendPathComponent("v1")
        url.appendPathComponent("subscriptions")
        url.appendPathComponent(subscription.id.uuidString)

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-text>"
            let msg = "Request to \(url.absoluteString) failed with status \(http.statusCode): \(body)"
            throw NSError(domain: "SubscriptionStore", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // Success - remove locally
        await MainActor.run {
            self.remove(subscription)
        }
    }

    /// Clear in-memory subscriptions (keeps the setter encapsulated).
    func clear() {
        self.subscriptions = []
    }
}
