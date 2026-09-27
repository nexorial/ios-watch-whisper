import Foundation

public enum MacAddress {
    public static func ipv4(_ input: String) -> String? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part), (0...255).contains(number) else { return nil }
            numbers.append(number)
        }
        guard numbers[0] > 0, numbers[0] < 224, numbers[0] != 127 else { return nil }
        return numbers.map(String.init).joined(separator: ".")
    }
}

public enum WiFiConnectionGuidance {
    public static func message(for error: Error, address: String) -> String {
        guard let error = error as? URLError else { return "连接未完成：\(error.localizedDescription)" }
        switch error.code {
        case .notConnectedToInternet:
            return "手表暂无可用网络。请在「设置 → Wi-Fi」核对网络，并与 Mac 连接同一局域网。"
        case .cannotConnectToHost, .timedOut, .cannotFindHost, .networkConnectionLost:
            return "无法连接 Mac（\(address)）。请确认 Mac 软件显示「Wi-Fi 已就绪」，并核对其 Mac IP 与这里一致。将自动重试，无需重新配对。"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled:
            return "无法验证 Mac 的安全连接。请确认 IP 属于原来配对的 Mac；更换电脑后需重新配置手表 App。"
        default:
            return "Wi-Fi 连接失败：\(error.localizedDescription)。请先检查 Mac 的接收服务状态。"
        }
    }
}
