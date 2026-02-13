//
//  ContentView.swift
//  Subscription Tracker
//
//  Created by Oleksandr Klosovych on 11.02.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var auth = AuthStore()
    @StateObject private var subs = SubscriptionStore()
    @State private var loadingSubscriptions: Bool = false
    @State private var subsError: String?
    @State private var hasFetchedSubscriptions: Bool = false

    // Presentation state for Add sheet
    @State private var showingAddSheet: Bool = false

    // Focus state for keyboard management
    @FocusState private var emailFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if auth.isAuthenticated {
                NavigationView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Hello user")
                                .font(.title)
                            Spacer()
                            Button("Logout") {
                                auth.logout()
                            }
                            .buttonStyle(.bordered)
                        }

                        if loadingSubscriptions {
                            ProgressView("Loading subscriptions...")
                        } else if let err = subsError {
                            Text("Failed to load: \(err)")
                                .foregroundColor(.red)
                        } else if subs.subscriptions.isEmpty {
                            Text("No subscriptions")
                                .foregroundColor(.secondary)
                        } else {
                            List(subs.subscriptions) { s in
                                VStack(alignment: .leading) {
                                    Text(s.name)
                                        .font(.headline)
                                    HStack {
                                        Text(String(format: "%.2f %@", s.price, ""))
                                            .font(.subheadline)
                                        Spacer()
                                        Text(s.nextDueDate, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .listStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(20)
                    .navigationTitle("Subscriptions")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showingAddSheet = true }) {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .onAppear {
                    Task {
                        if !hasFetchedSubscriptions {
                            await fetchSubscriptionsIfNeeded()
                        }
                    }
                }
                .onChange(of: auth.isAuthenticated) { newValue in
                    if newValue {
                        Task {
                            if !hasFetchedSubscriptions {
                                await fetchSubscriptionsIfNeeded()
                            }
                        }
                    } else {
                        // Clear subscriptions when logged out
                        subs.clear()
                        hasFetchedSubscriptions = false
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    AddSubscriptionView(store: subs)
                }
            } else {
                HStack(spacing: 12) {
                    TextField("Email", text: $auth.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .focused($emailFieldFocused)

                    Button("Login / Register") {
                        // Dismiss keyboard using SwiftUI FocusState instead of sending a global action
                        emailFieldFocused = false

                        Task {
                            // small delay to allow keyboard to dismiss and layout to settle
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                            await auth.login()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(auth.email.isEmpty || auth.loading)
                }
                .padding(.horizontal, 20)
            }
        }
        .alert(isPresented: Binding(get: { auth.errorMessage != nil || subsError != nil }, set: { if !$0 { auth.errorMessage = nil; subsError = nil } })) {
            Alert(title: Text("Error"), message: Text(auth.errorMessage ?? subsError ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private func fetchSubscriptionsIfNeeded() async {
        // Only attempt to fetch if authenticated flag is true and a token exists in Keychain
        guard auth.isAuthenticated else { return }

        // mark we've started fetch to avoid duplicate attempts
        hasFetchedSubscriptions = true

        // Show loading state
        DispatchQueue.main.async {
            self.loadingSubscriptions = true
            self.subsError = nil
        }

        do {
            try await subs.refreshFromServer()
        } catch {
            DispatchQueue.main.async {
                self.subsError = error.localizedDescription
            }
        }

        DispatchQueue.main.async {
            self.loadingSubscriptions = false
        }
    }
}

#Preview {
    ContentView()
}
