import Foundation
import Combine
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    @Published var email: String = ""
    @Published var isAuthenticated: Bool = false
    @Published var loading: Bool = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Read presence flag from UserDefaults to avoid Keychain access at launch
        let present = UserDefaults.standard.bool(forKey: KeychainKeys.presenceFlag)
        self.isAuthenticated = present
    }

    func login() async {
        guard !email.isEmpty else { return }
        loading = true
        defer { loading = false }

        await withCheckedContinuation { continuation in
            AuthService.authenticate(email: email) { [weak self] result in
                // Handle network callback off the main thread if storage is required
                switch result {
                case .success(let resp):
                    // Store token on a background queue to avoid blocking the main thread / triggering system UI there.
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try AuthService.storeToken(resp.token)
                            DispatchQueue.main.async {
                                self?.isAuthenticated = true
                                self?.errorMessage = nil
                                continuation.resume()
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self?.errorMessage = "Failed to store token: \(error)"
                                continuation.resume()
                            }
                        }
                    }
                case .failure(let err):
                    DispatchQueue.main.async {
                        self?.errorMessage = "Login failed: \(err)"
                        continuation.resume()
                    }
                }
            }
        }
    }

    func logout() {
        do {
            try AuthService.deleteToken()
        } catch {
            print("Failed to delete token: \(error)")
        }
        isAuthenticated = false
    }
}
