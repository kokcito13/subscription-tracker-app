import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubscriptionStore
    var subscription: AppSubscription

    @State private var name: String
    @State private var price: String
    @State private var cycle: BillingCycle
    @State private var date: Date

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case price
    }

    init(store: SubscriptionStore, subscription: AppSubscription) {
        self.store = store
        self.subscription = subscription
        _name = State(initialValue: subscription.name)
        _price = State(initialValue: String(format: "%.2f", subscription.price))
        _cycle = State(initialValue: subscription.billingCycle)
        _date = State(initialValue: subscription.nextDueDate)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Price", text: $price)
                        .focused($focusedField, equals: .price)
                    DatePicker("Next due", selection: $date, displayedComponents: .date)
                }
                
                Section(header: Text("Billing Cycle")) {
                    BillingCycleSelector(selectedCycle: $cycle)
                        .frame(height: 60)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if isSubmitting {
                    Section { ProgressView("Saving...") }
                }
            }
            .navigationTitle("Edit Subscription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focusedField = nil

                        Task {
                            // Give time for focus update
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            await saveTapped()
                        }
                    }
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(price.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        Task {
                            // Give time for focus update
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            dismiss()
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onDisappear {
                focusedField = nil
            }
        }
    }

    private func billingPeriodString(from cycle: BillingCycle) -> String {
        switch cycle {
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        }
    }

    private func saveTapped() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let p = Double(price.replacingOccurrences(of: ",", with: ".")) else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Build payload matching backend expectations (include id)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let nextBillingDate = formatter.string(from: date)

        let comps = Calendar.current.dateComponents([.day, .month], from: date)
        let day = comps.day ?? 1
        let month = comps.month ?? 1

        let payload: [String: Any] = [
            "id": subscription.id.uuidString,
            "name": trimmedName,
            "amount": String(format: "%.2f", p),
            "currency": "USD",
            "billingPeriod": billingPeriodString(from: cycle),
            "billingDayOfMonth": day,
            "billingMonthOfYear": month,
            "nextBillingDate": nextBillingDate,
            "category": "other",
            "status": subscription.isActive ? "active" : "inactive"
        ]

        do {
            guard AuthService.hasTokenInKeychain() else {
                throw NSError(domain: "EditSubscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token found in Keychain"])
            }
            let token = try await AuthService.retrieveToken()

            // Build URL PATCH /v1/subscriptions/{id}
            var url = Config.backendHost
            url.appendPathComponent("v1")
            url.appendPathComponent("subscriptions")
            url.appendPathComponent(subscription.id.uuidString)

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    // Success - refresh from server and dismiss
                    do {
                        try await store.refreshFromServer()
                    } catch {
                        print("Refresh after edit failed: \(error)")
                    }

                    try? await Task.sleep(nanoseconds: 50_000_000)
                    dismiss()
                    return
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-text>"
                    throw NSError(domain: "EditSubscription", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned \(http.statusCode): \(body)"])
                }
            }

            throw NSError(domain: "EditSubscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from server"])
        } catch {
            errorMessage = "Failed to edit subscription: \(error.localizedDescription)"
        }
    }
}

#Preview {
    EditSubscriptionView(store: SubscriptionStore(), subscription: AppSubscription(name: "Test", price: 9.99, billingCycle: .monthly, nextDueDate: Date()))
}
