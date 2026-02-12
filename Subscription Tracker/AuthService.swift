import Foundation
import LocalAuthentication

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable {
    let id: String
    let email: String
}

enum AuthError: Error {
    case invalidURL
    case serverError(String)
    case keychainError(OSStatus)
    case missingData
    case biometricFailed(Error)
}

enum KeychainKeys {
    static let service = "subscription-tracker"
    static let account = "authToken"
    static let presenceFlag = "hasAuthToken"
}

final class AuthService {
    static func authenticate(email: String, completion: @escaping (Result<AuthResponse, Error>) -> Void) {
        let url = Config.backendHost.appendingPathComponent("api/auth")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["email": email]
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(AuthError.missingData)) }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(decoded)) }
            } catch {
                // Try decode error message
                if let s = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { completion(.failure(AuthError.serverError(s))) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }

    // Store token in Keychain using accessible-when-unlocked attribute to avoid system UI during store
    static func storeToken(_ token: String) throws {
        let tokenData = Data(token.utf8)

        // Prepare query for adding. If item exists, we'll update instead.
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account,
            kSecValueData: tokenData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: KeychainKeys.service,
                kSecAttrAccount: KeychainKeys.account
            ]
            let update: [CFString: Any] = [
                kSecValueData: tokenData
            ]
            let ustatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if ustatus != errSecSuccess {
                throw AuthError.keychainError(ustatus)
            }
        } else if status != errSecSuccess {
            throw AuthError.keychainError(status)
        }

        // Mark presence in UserDefaults to avoid Keychain calls at launch
        UserDefaults.standard.set(true, forKey: KeychainKeys.presenceFlag)
    }

    // Retrieve token after performing biometric authentication (Face ID).
    // This is now async and performs evaluatePolicy on the main thread, reading Keychain on a background queue.
    static func retrieveToken(withPrompt prompt: String = "Unlock to access token") async throws -> String {
        let context = LAContext()
        var authError: NSError?
        let reason = prompt

        // Determine available policy: prefer biometrics, otherwise deviceOwnerAuthentication
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        // Evaluate policy on main thread to allow system UI to present
        let didAuthenticate: Bool
        do {
            didAuthenticate = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                DispatchQueue.main.async {
                    context.evaluatePolicy(policy, localizedReason: reason) { success, evalError in
                        if success {
                            continuation.resume(returning: true)
                        } else {
                            continuation.resume(throwing: evalError ?? NSError(domain: "AuthService", code: -1, userInfo: nil))
                        }
                    }
                }
            }
        } catch {
            throw AuthError.biometricFailed(error)
        }

        if !didAuthenticate {
            throw AuthError.biometricFailed(NSError(domain: "AuthService", code: -1, userInfo: nil))
        }

        // Read token from keychain on a background queue
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: KeychainKeys.service,
                    kSecAttrAccount: KeychainKeys.account,
                    kSecReturnData: true,
                    kSecMatchLimit: kSecMatchLimitOne
                ]

                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                if status == errSecSuccess {
                    if let data = item as? Data, let token = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(throwing: AuthError.missingData)
                    }
                } else {
                    continuation.resume(throwing: AuthError.keychainError(status))
                }
            }
        }
    }

    // Check presence of a token without prompting biometric UI
    static func hasTokenInKeychain() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    static func deleteToken() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw AuthError.keychainError(status)
        }

        // Clear presence flag
        UserDefaults.standard.set(false, forKey: KeychainKeys.presenceFlag)
    }
}
