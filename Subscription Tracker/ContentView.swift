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
    @State private var editingSubscription: AppSubscription?

    // Focus state for keyboard management
    @FocusState private var emailFieldFocused: Bool

    // Deletion state
    @State private var deletionCandidate: AppSubscription?
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    // Profile navigation state
    @State private var showingProfile: Bool = false


    var body: some View {
        NavigationStack {
            ZStack {
            // Background: light gradient with soft vignette / blobs
            LinearGradient(colors: [Color.primary.opacity(0.02), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // soft decorative blobs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.03))
                        .frame(width: 260, height: 260)
                        .blur(radius: 60)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.2)

                    Circle()
                        .fill(Color.purple.opacity(0.03))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .offset(x: geo.size.width * 0.4, y: -geo.size.height * 0.15)
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                // Top header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greetingText)
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(Color.primary)
                            .lineLimit(1)

                        Text("Manage your subscriptions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Profile button (only shown when authenticated)
                    if auth.isAuthenticated {
                        Button(action: { showingProfile = true }) {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .foregroundStyle(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .accessibilityLabel("Profile")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Summary cards (only shown when authenticated)
                if auth.isAuthenticated {
                    AdaptiveSummaryView(monthly: subs.totalMonthlyFormatted, yearly: subs.totalYearlyFormatted)
                        .padding(.horizontal, 20)
                }

                // Section title + add button (only shown when authenticated)
                if auth.isAuthenticated {
                    HStack(alignment: .center) {
                        Text("My Subscriptions")
                            .font(.title2).fontWeight(.semibold)
                            .foregroundColor(Color.primary)

                        Spacer()

                        FloatingAddButton(action: { showingAddSheet = true })
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }

                // Content
                if auth.isAuthenticated {
                    if loadingSubscriptions {
                        ProgressView("Loading subscriptions...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let err = subsError {
                        Text("Failed to load: \(err)")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if subs.subscriptions.isEmpty {
                        Text("No subscriptions")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 14) {
                                ForEach(subs.subscriptions) { s in
                                    SubscriptionCard(
                                        iconName: s.iconName ?? "cloud.fill",
                                        name: s.name,
                                        priceText: priceText(for: s),
                                        renewText: renewText(for: s),
                                        onEdit: { editingSubscription = s },
                                        onDelete: {
                                            deletionCandidate = s
                                            showDeleteConfirmation = true
                                        }
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.bottom, 92) // enough space for bottom nav
                        }
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

                Spacer(minLength: 0)
            }
            .onAppear { Task { if auth.isAuthenticated && !hasFetchedSubscriptions { await fetchSubscriptionsIfNeeded() } } }
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
            .sheet(isPresented: $showingProfile) {
                ProfileView()
                    .environmentObject(auth)
            }

            // Delete confirmation overlay
            if showDeleteConfirmation {
                Color.black.opacity(0.4).ignoresSafeArea().transition(.opacity)

                VStack(spacing: 16) {
                    Text("Do you really want to delete \(deletionCandidate?.name ?? "this subscription")?")
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
                                isDeleting = true
                                do {
                                    try await subs.deleteFromServer(subscription)
                                } catch {
                                    subsError = "Failed to delete: \(error.localizedDescription)"
                                }
                                isDeleting = false
                                deletionCandidate = nil
                                showDeleteConfirmation = false
                            }
                        } label: {
                            Text(isDeleting ? "Deleting..." : "Delete").frame(minWidth: 100)
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

        }
        .alert(isPresented: Binding(get: { auth.errorMessage != nil || subsError != nil }, set: { if !$0 { auth.errorMessage = nil; subsError = nil } })) {
            Alert(title: Text("Error"), message: Text(auth.errorMessage ?? subsError ?? ""), dismissButton: .default(Text("OK")))
        }
        }
    }

    // MARK: - Helpers
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning"
        case 12..<18: greeting = "Good day"
        default:      greeting = "Good evening"
        }
        return greeting
    }

    private func priceText(for s: AppSubscription) -> String {
        if s.billingPeriod == .yearly {
            return "\(String(format: "%.2f", s.price)) / year"
        }
        return "\(String(format: "%.2f", s.price)) / month"
    }

    private func renewText(for s: AppSubscription) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Renews on \(formatter.string(from: s.nextDueDate))"
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

// MARK: - Supporting Views and Types

struct AdaptiveSummaryView: View {
    var monthly: String
    var yearly: String

    var body: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Monthly",
                value: monthly,
                accent: [Color(hex: "4F8EF7"), Color(hex: "7B5EF8")],
                icon: "creditcard.fill"
            )
            SummaryCard(
                title: "Yearly",
                value: yearly,
                accent: [Color(hex: "F7934F"), Color(hex: "F85E9A")],
                icon: "calendar"
            )
        }
    }
}

struct SummaryCard: View {
    var title: String
    var value: String
    var accent: [Color]
    var icon: String

    var body: some View {
        HStack(spacing: 10) {
            // Accent icon bubble
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent[0].opacity(0.08), accent[1].opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [accent[0].opacity(0.4), accent[1].opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: accent[0].opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct SubscriptionCard: View {
    var iconName: String
    var name: String
    var priceText: String
    var renewText: String
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.blue)
            }

            // Price → Name → Renew
            VStack(alignment: .leading, spacing: 1) {
                Text(priceText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(renewText)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Actions
            VStack(spacing: 2) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Edit \(name)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Delete \(name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}

struct FloatingAddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Circle())
                .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 6)
        }
        .accessibilityLabel("Add subscription")
    }
}



#Preview {
    ContentView()
}
