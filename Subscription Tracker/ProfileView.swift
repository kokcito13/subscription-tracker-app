import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Background — matches ContentView
                LinearGradient(
                    colors: [Color.primary.opacity(0.02), Color.gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

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

                VStack(spacing: 24) {
                    // Avatar
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 32)

                    // Email card
                    if !auth.email.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                            Text(auth.email)
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                        .padding(.horizontal, 20)
                    }

                    Spacer()

                    // Logout button
                    Button(action: {
                        auth.logout()
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Sign Out")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.red.opacity(0.85), Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.red.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
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
