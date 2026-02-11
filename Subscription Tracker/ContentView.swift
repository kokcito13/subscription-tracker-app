//
//  ContentView.swift
//  Subscription Tracker
//
//  Created by Oleksandr Klosovych on 11.02.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = SubscriptionStore()
    @State private var showingAdd = false

    var body: some View {
        NavigationView {
            List {
                if store.subscriptions.isEmpty {
                    Text("No subscriptions yet — tap + to add one")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($store.subscriptions) { $sub in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(sub.name).font(.headline)
                                Text(sub.billingCycle.displayName + " • " + String(format: "$%.2f", sub.price))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Active", isOn: $sub.isActive)
                                .labelsHidden()
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: store.remove)
                }
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAdd = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSubscriptionView(store: store)
            }
        }
    }
}

#Preview {
    ContentView()
}
