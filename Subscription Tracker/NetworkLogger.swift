import Foundation

#if DEBUG

/// A URLProtocol that intercepts HTTP/HTTPS requests and logs the URL, request body, and response body.
/// It avoids recursion by setting a request property and creating a backing URLSession that does not include this protocol.
final class NetworkLogger: URLProtocol {
    private static let handledKey = "NetworkLoggerHandled"
    // renamed to avoid conflicting with URLProtocol/URLSessionTask APIs
    private var backingTask: URLSessionDataTask?
    private var receivedData = Data()
    private var receivedResponse: URLResponse?

    // Maximum number of bytes to keep when logging bodies
    private static let maxLogBodyBytes = 10 * 1024 // 10 KB

    override class func canInit(with request: URLRequest) -> Bool {
        // Only handle http/https and only if we didn't already mark the request.
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        if !(scheme == "http" || scheme == "https") { return false }
        if URLProtocol.property(forKey: handledKey, in: request) != nil { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Make a mutable copy and mark it handled so we don't intercept our own forwarded request.
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: NetworkLogger.handledKey, in: mutableRequest)

        // Log request details
        logRequest(mutableRequest as URLRequest)

        // Create backing session configuration without this protocol to avoid loops
        let config = URLSessionConfiguration.default
        if let classes = config.protocolClasses {
            config.protocolClasses = classes.filter { $0 != NetworkLogger.self }
        }

        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        backingTask = session.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                self.logError(error)
                return
            }

            if let response = response {
                self.receivedResponse = response
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data = data {
                self.receivedData.append(data)
                self.client?.urlProtocol(self, didLoad: data)
            }

            // Log response after we've forwarded it
            self.logResponse(response: response, data: self.receivedData)

            self.client?.urlProtocolDidFinishLoading(self)
        }

        backingTask?.resume()
    }

    override func stopLoading() {
        backingTask?.cancel()
        backingTask = nil
    }

    // MARK: - Logging helpers

    private func logRequest(_ request: URLRequest) {
        guard let url = request.url else { return }

        print("\n→→→ Network Request →→→")
        print("URL: \(url.absoluteString)")

        // Log headers with redaction
        if let headers = request.allHTTPHeaderFields {
            var redacted = headers
            if redacted.keys.contains("Authorization") {
                redacted["Authorization"] = "<REDACTED>"
            }
            print("Request headers: \(redacted)")
        }

        // Log body
        if let body = request.httpBody {
            logBody(data: body, prefix: "Request body:")
        } else if let stream = request.httpBodyStream {
            // Try to read up to limit from the stream
            if let data = readDataFromInputStream(stream, maxBytes: NetworkLogger.maxLogBodyBytes) {
                logBody(data: data, prefix: "Request body (from stream):")
            } else {
                print("Request body: <unable to read stream>")
            }
        } else {
            print("Request body: <none>")
        }
        print("←←← End Request ←←←\n")
    }

    private func logResponse(response: URLResponse?, data: Data) {
        print("\n→→→ Network Response →→→")
        if let httpResponse = response as? HTTPURLResponse {
            print("URL: \(httpResponse.url?.absoluteString ?? "-")")
            print("Status code: \(httpResponse.statusCode)")
            var headers = httpResponse.allHeaderFields
            // redact values with case-insensitive match for Authorization
            for key in headers.keys {
                if let keyStr = key as? String, keyStr.caseInsensitiveCompare("Authorization") == .orderedSame {
                    headers[key] = "<REDACTED>"
                }
            }
            print("Response headers: \(headers)")
        } else if let url = response?.url {
            print("URL: \(url.absoluteString)")
        }

        if data.count > 0 {
            logBody(data: data, prefix: "Response body:")
        } else {
            print("Response body: <empty>")
        }
        print("←←← End Response ←←←\n")
    }

    private func logError(_ error: Error) {
        print("\n→→→ Network Error →→→")
        print("URL: \(request.url?.absoluteString ?? "-")")
        print("Error: \(error.localizedDescription)")
        print("←←← End Error ←←←\n")
    }

    private func logBody(data: Data, prefix: String) {
        let originalCount = data.count
        let toKeep = min(originalCount, NetworkLogger.maxLogBodyBytes)
        let truncated = originalCount > toKeep
        let slice = data.prefix(toKeep)

        if let text = String(data: slice, encoding: .utf8) {
            // Try to pretty-print JSON if possible
            if let pretty = prettyPrintedJSON(from: slice) {
                print("\(prefix) \(pretty)\(truncated ? " (truncated)" : "")")
            } else {
                print("\(prefix) \(text)\(truncated ? " (truncated)" : "")")
            }
        } else {
            print("\(prefix) <non-text, \(originalCount) bytes>\(truncated ? " (truncated)" : "")")
        }
    }

    private func prettyPrintedJSON(from data: Data) -> String? {
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func readDataFromInputStream(_ input: InputStream, maxBytes: Int) -> Data? {
        input.open()
        defer { input.close() }
        let bufferSize = 1024
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while input.hasBytesAvailable && data.count < maxBytes {
            let toRead = min(bufferSize, maxBytes - data.count)
            let read = input.read(buffer, maxLength: toRead)
            if read < 0 {
                return nil
            } else if read == 0 {
                break
            } else {
                data.append(buffer, count: read)
            }
        }
        return data
    }
}

#endif

