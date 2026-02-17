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

    // State for editing a single subscription
    @State private var editingSubscription: Subscription?

    // Focus state for keyboard management
    @FocusState private var emailFieldFocused: Bool

    // Deletion state
    @State private var deletionCandidate: Subscription?
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirmation: Bool = false

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
                            Button("Logout") { auth.logout() }
                                .buttonStyle(.bordered)
                        }

                        // Added: Summary stats row
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Monthly:")
                                    .font(.headline)
                                Spacer()
                                Text(subs.totalMonthlyFormatted)
                                    .font(.headline)
                            }
                            HStack {
                                Text("Yearly:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(subs.totalYearlyFormatted)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)

                        if loadingSubscriptions {
                            ProgressView("Loading subscriptions...")
                        } else if let err = subsError {
                            Text("Failed to load: \(err)")
                                .foregroundColor(.red)
                        } else if subs.subscriptions.isEmpty {
                            Text("No subscriptions")
                                .foregroundColor(.secondary)
                        } else {
                            List {
                                ForEach(subs.subscriptions) { s in
                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading) {
                                            Text(s.name).font(.headline)
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

                                        Spacer()

                                        if isDeleting && deletionCandidate?.id == s.id {
                                            ProgressView().padding(.leading, 8)
                                        } else {
                                            // Edit button
                                            Button(action: {
                                                editingSubscription = s
                                            }) {
                                                Image(systemName: "pencil")
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 8)
                                            .accessibilityLabel("Edit \(s.name)")

                                            Button(action: {
                                                print("[ContentView] delete tapped for \(s.name) id=\(s.id)")
                                                deletionCandidate = s
                                                showDeleteConfirmation = true
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 8)
                                            .accessibilityLabel("Delete \(s.name)")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deletionCandidate = s
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
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
                .onAppear { Task { if !hasFetchedSubscriptions { await fetchSubscriptionsIfNeeded() } } }
                .onChange(of: auth.isAuthenticated) { newValue in
                    if newValue {
                        Task { if !hasFetchedSubscriptions { await fetchSubscriptionsIfNeeded() } }
                    } else {
                        subs.clear()
                        hasFetchedSubscriptions = false
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    AddSubscriptionView(store: subs)
                }
                .sheet(item: $editingSubscription) { sub in
                    EditSubscriptionView(store: subs, subscription: sub)
                }
                // Small debug banner to show the selected candidate immediately
                if let cand = deletionCandidate {
                    HStack {
                        Spacer()
                        Text("Delete: \(cand.name)")
                            .padding(8)
                            .background(Color.yellow.opacity(0.9))
                            .cornerRadius(8)
                            .padding()
                    }
                    .transition(.move(edge: .top))
                }
                // Inline overlay dialog (global) - placed after debug banner to ensure it sits on top
                if showDeleteConfirmation {
                    Color.black.opacity(0.4).ignoresSafeArea().transition(.opacity)

                    VStack(spacing: 16) {
                        Text("Do you real want to delete \(deletionCandidate?.name ?? "this subscription")?")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding()

                        HStack(spacing: 12) {
                            Button(action: {
                                deletionCandidate = nil
                                showDeleteConfirmation = false
                            }) {
                                Text("Cancel").frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                Task {
                                    guard let subscription = deletionCandidate else { return }
                                    print("[ContentView] confirm delete for \(subscription.name) id=\(subscription.id)")
                                    isDeleting = true
                                    do {
                                        try await subs.deleteFromServer(subscription)
                                        print("[ContentView] delete completed for \(subscription.name)")
                                    } catch {
                                        subsError = "Failed to delete: \(error.localizedDescription)"
                                        print("[ContentView] delete failed: \(error)")
                                    }
                                    isDeleting = false
                                    deletionCandidate = nil
                                    showDeleteConfirmation = false
                                }
                            } label: {
                                Text("Delete").frame(minWidth: 100)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom, 10)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(40)
                    .zIndex(1)
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
                        emailFieldFocused = false
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000)
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
        guard auth.isAuthenticated else { return }
        hasFetchedSubscriptions = true
        DispatchQueue.main.async { self.loadingSubscriptions = true; self.subsError = nil }
        do { try await subs.refreshFromServer() }
        catch { DispatchQueue.main.async { self.subsError = error.localizedDescription } }
        DispatchQueue.main.async { self.loadingSubscriptions = false }
    }
}

#Preview {
    ContentView()
}
