//
//  ProfileView.swift
//  Subscription Tracker
//
//  Created for navigation from Profile circle
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Profile icon
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.top, 40)
                
                // User email
                if !auth.email.isEmpty {
                    Text(auth.email)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Logout button
                Button(action: {
                    auth.logout()
                    dismiss()
                }) {
                    Text("Logout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthStore())
}
