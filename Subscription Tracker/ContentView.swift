//
//  ContentView.swift
//  Subscription Tracker
//
//  Created by Oleksandr Klosovych on 11.02.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var auth = AuthStore()

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if auth.isAuthenticated {
                Text("Hello user")
                    .font(.title)
            } else {
                HStack(spacing: 12) {
                    TextField("Email", text: $auth.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    Button("Login / Register") {
                        // Dismiss keyboard before performing authentication to avoid keyboard/system UI conflicts
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

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
        .alert(isPresented: Binding(get: { auth.errorMessage != nil }, set: { if !$0 { auth.errorMessage = nil } })) {
            Alert(title: Text("Error"), message: Text(auth.errorMessage ?? ""), dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    ContentView()
}
