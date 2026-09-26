import Foundation
import Network
import Security
import MicodexCore

final class TLSHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPEnvelope) async -> (Int, WiFiReply)
    private let queue = DispatchQueue(label: "Micodex.https")
    private var listener: NWListener?
    private var connections: [UUID: HTTPConnection] = [:]
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }
    func start(identity: SecIdentity, address: String, portNumber: UInt16 = LocalTLSIdentity.port, onState: @escaping @Sendable (String) -> Void) throws {
        let tls = NWProtocolTLS.Options()
        guard let identity = sec_identity_create(identity) else { throw LocalTLSIdentity.Failure("无法创建 TLS 身份。") }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        let port = NWEndpoint.Port(rawValue: portNumber)!
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: port)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: onState("Wi-Fi 已就绪 · \(address)")
            case .failed(let error): onState("Wi-Fi 服务失败：\(error.localizedDescription)")
            case .waiting(let error): onState("等待本地网络：\(error.localizedDescription)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 16 else { connection.cancel(); return }
            let id = UUID()
            let client = HTTPConnection(connection: connection, queue: self.queue, handler: self.handler) { [weak self] in
                self?.connections[id] = nil
            }
            self.connections[id] = client; client.start()
        }
        listener.start(queue: queue)
    }
    func stop(completion: @escaping @Sendable () -> Void = {}) {
        // Retain the server until cancellation completes; a weak capture can
        // disappear before releasing its port when a host replaces the server.
        queue.async {
            guard let listener = self.listener else { completion(); return }
            listener.stateUpdateHandler = { state in
                guard case .cancelled = state else { return }
                listener.stateUpdateHandler = nil
                self.listener = nil
                completion()
            }
            let clients = Array(self.connections.values); self.connections = [:]
            clients.forEach { $0.stop() }
            listener.cancel()
        }
    }
}

private final class HTTPConnection: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let handler: TLSHTTPServer.Handler
    let onClose: () -> Void
    var decoder = HTTPEnvelopeDecoder()
    var timeout: DispatchWorkItem?
    var stopped = false
    var inputEnded = false
    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping TLSHTTPServer.Handler, onClose: @escaping () -> Void) {
        self.connection = connection; self.queue = queue; self.handler = handler; self.onClose = onClose
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.read()
            case .failed, .cancelled: self?.stop()
            default: break
            }
        }
        connection.start(queue: queue); armTimeout()
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        timeout?.cancel(); connection.cancel(); onClose()
    }
    func armTimeout() {
        timeout?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = task; queue.asyncAfter(deadline: .now() + 12, execute: task)
    }
    func read() {
        guard !stopped else { return }; armTimeout()
        do {
            if let request = try decoder.next() {
                Task {
                    let (status, reply) = await handler(request)
                    guard let body = try? JSONEncoder().encode(reply) else { queue.async { self.stop() }; return }
                    let head = "HTTP/1.1 \(status) Response\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: \(request.close ? "close" : "keep-alive")\r\n\r\n"
                    queue.async {
                        guard !self.stopped else { return }
                        self.connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] error in
                            guard let self else { return }
                            if error != nil || request.close || self.inputEnded { self.stop() } else { self.read() }
                        })
                    }
                }
                return
            }
        } catch { stop(); return }
        guard !inputEnded else { stop(); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, complete, error in
            guard let self else { return }
            guard error == nil else { self.stop(); return }
            if let data, !data.isEmpty {
                do { try self.decoder.append(data) } catch { self.stop(); return }
            }
            self.inputEnded = complete
            self.read()
        }
    }
}
