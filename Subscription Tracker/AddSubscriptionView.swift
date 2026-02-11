import SwiftUI

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubscriptionStore

    @State private var name: String = ""
    @State private var price: String = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var date: Date = Date()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Name", text: $name)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    Picker("Cycle", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    DatePicker("Next due", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Subscription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let p = Double(price.replacingOccurrences(of: ",", with: ".")), !name.isEmpty else {
                            return
                        }
                        let sub = Subscription(name: name, price: p, billingCycle: cycle, nextDueDate: date)
                        store.add(sub)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AddSubscriptionView(store: SubscriptionStore())
}
