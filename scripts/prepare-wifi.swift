import Foundation

@main
struct PrepareWiFi {
    static func main() {
        do { try prepare() }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func prepare() throws {
        let identity = try LocalTLSIdentity.prepare()
        guard let address = LocalTLSIdentity.localAddress() else { throw LocalTLSIdentity.Failure("请先连接 Mac 的局域网。") }
        let result: [String: Any] = ["host": address, "port": LocalTLSIdentity.port, "pin": identity.fingerprint]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
