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
    // In-memory cache of the token to allow immediate use right after login without
    // requiring a Keychain read or biometric prompt. This cache only lasts for the
    // lifetime of the process (exactly what we want for immediate fetches).
    private static var cachedToken: String?
    // Single-flight Task for retrieveToken to avoid multiple concurrent biometric prompts
    private static var retrieveTask: Task<String, Error>?
    // Serial queue to atomically create/check the retrieveTask
    private static let retrieveTaskQueue = DispatchQueue(label: "AuthService.retrieveTaskQueue")

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
        // Cache token in memory immediately to avoid races where callers request the token
        // before Keychain storage completes (this prevents extra biometric prompts).
        cachedToken = token

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
        // If we have a cached token in-memory, return it immediately (no biometric required).
        if let t = cachedToken {
            return t
        }

        // Atomically check/create a single-flight Task so multiple concurrent callers
        // don't each create and run the biometric flow.
        var taskToAwait: Task<String, Error>!
        AuthService.retrieveTaskQueue.sync {
            if let existing = retrieveTask {
                taskToAwait = existing
            } else {
                let newTask = Task<String, Error> {
                    // First, attempt a non-interactive Keychain read (no biometric prompt)
                    if let token = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<String, Error>) in
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
                    }) {
                        cachedToken = token
                        return token
                    }

                    // Otherwise, perform biometric authentication and read using kSecUseAuthenticationContext to allow access.
                    let context = LAContext()
                    var authError: NSError?
                    let reason = prompt

                    let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

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

                    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let query: [CFString: Any] = [
                                kSecClass: kSecClassGenericPassword,
                                kSecAttrService: KeychainKeys.service,
                                kSecAttrAccount: KeychainKeys.account,
                                kSecReturnData: true,
                                kSecMatchLimit: kSecMatchLimitOne,
                                kSecUseAuthenticationContext: context
                            ]

                            var item: CFTypeRef?
                            let status = SecItemCopyMatching(query as CFDictionary, &item)
                            if status == errSecSuccess {
                                if let data = item as? Data, let token = String(data: data, encoding: .utf8) {
                                    cachedToken = token
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
                retrieveTask = newTask
                taskToAwait = newTask
            }
        }

        // Await the task outside the lock
        defer {
            // clear retrieveTask when finished
            AuthService.retrieveTaskQueue.async {
                retrieveTask = nil
            }
        }

        return try await taskToAwait.value
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

        // Clear cached token in memory
        cachedToken = nil
    }
}
