import Foundation
import Security
import CryptoKit

public final class PinnedHTTPSClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    public let baseURL: URL
    private let fingerprint: String
    private var session: URLSession!
    public init(host: String, port: UInt16 = 8766, fingerprint: String) throws {
        guard !host.isEmpty, host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }),
              fingerprint.count == 64, fingerprint.allSatisfy({ $0.isHexDigit }),
              let url = URL(string: "https://\(host):\(port)") else { throw URLError(.badURL) }
        baseURL = url; self.fingerprint = fingerprint.lowercased()
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    public func request(_ path: String, _ body: WiFiRequest? = nil) async throws -> WiFiReply {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https",
              http.url?.host == baseURL.host, data.count <= 32_768 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(WiFiReply.self, from: data)
    }
    public func invalidate() { session.invalidateAndCancel() }
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == baseURL.host,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let actual = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        // The complete certificate pin is provisioned over the trusted developer
        // install path. It identifies this Mac independently of its changing LAN IP.
        guard SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
