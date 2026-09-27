import Foundation
import MicodexCore

@main
struct PrepareWiFi {
    static func main() {
        do { try prepare() }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func prepare() throws {
        let identity = try LocalTLSIdentity.prepare()
        guard let address = LocalTLSIdentity.localAddress() else { throw LocalTLSIdentity.Failure(L10n.message("Connect Mac to your local network first.")) }
        let result: [String: Any] = ["host": address, "port": LocalTLSIdentity.port, "pin": identity.fingerprint]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
