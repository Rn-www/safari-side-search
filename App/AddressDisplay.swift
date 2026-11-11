import Foundation

enum AddressDisplay {
    static func text(for url: URL, showFullURL: Bool) -> String {
        guard !showFullURL, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              var host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.contains(":"), !host.hasPrefix("[") { host = "[" + host + "]" }
        if let port = url.port { host += ":\(port)" }
        // Keep HTTP explicit rather than making it look like an HTTPS origin.
        return url.scheme?.lowercased() == "http" ? "http://" + host : host
    }
}
