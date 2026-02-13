import SwiftUI
import UIKit

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubscriptionStore

    @State private var name: String = ""
    @State private var price: String = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var date: Date = Date()

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case price
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .price)
                    Picker("Cycle", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    DatePicker("Next due", selection: $date, displayedComponents: .date)
                }

                if isSubmitting {
                    Section { ProgressView("Saving...") }
                }
            }
            .navigationTitle("Add Subscription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Dismiss keyboard via focus state first
                        focusedField = nil

                        // Also ensure the keyboard is fully resigned by calling UIApplication resign action on the main actor
                        Task {
                            await MainActor.run {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            // Small delay to allow the system to complete input teardown to avoid RTIInputSystemClient logs
                            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms

                            await saveTapped()
                        }
                    }
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(price.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Ensure keyboard is dismissed before dismissing the view
                        focusedField = nil
                        Task {
                            await MainActor.run {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
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
                // Clear any focus and explicitly resign keyboard to avoid performing operations on an invalid text input session.
                focusedField = nil
                Task {
                    await MainActor.run {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private func saveTapped() async {
        // Basic validation
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let p = Double(price.replacingOccurrences(of: ",", with: ".")) else { return }

        isSubmitting = true
        errorMessage = nil

        defer { isSubmitting = false }

        // Build payload matching backend expectations
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let nextBillingDate = formatter.string(from: date)

        // Extract day and month components
        let comps = Calendar.current.dateComponents([.day, .month], from: date)
        let day = comps.day ?? 1
        let month = comps.month ?? 1

        let payload: [String: Any] = [
            "name": trimmedName,
            "amount": String(format: "%.2f", p),
            "currency": "USD",
            "billingPeriod": billingPeriodString(from: cycle),
            "billingDayOfMonth": day,
            "billingMonthOfYear": month,
            "nextBillingDate": nextBillingDate,
            "category": "other"
        ]

        do {
            // Obtain token (may prompt biometric)
            let token = try await AuthService.retrieveToken()

            // Build URL
            var url = Config.backendHost
            url.appendPathComponent("v1")
            url.appendPathComponent("subscriptions")

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 201 {
                    // Success - refresh subscriptions from server and dismiss
                    do {
                        try await store.refreshFromServer()
                    } catch {
                        // If refresh fails, still dismiss but show message back in UI via SubscriptionStore's error handling
                        print("Refresh after create failed: \(error)")
                    }

                    // Ensure keyboard is dismissed and give system a moment before dismissing
                    await MainActor.run {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)

                    dismiss()
                    return
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-text>"
                    throw NSError(domain: "AddSubscription", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned \(http.statusCode): \(body)"])
                }
            }

            // If we got here, response wasn't HTTPURLResponse
            throw NSError(domain: "AddSubscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from server"])
        } catch {
            errorMessage = "Failed to add subscription: \(error.localizedDescription)"
        }
    }

    private func billingPeriodString(from cycle: BillingCycle) -> String {
        switch cycle {
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        }
    }
}

#Preview {
    AddSubscriptionView(store: SubscriptionStore())
}
