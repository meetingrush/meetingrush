import Foundation
import Network

/// Listens on `127.0.0.1` for the redirect Google's sign-in page sends back to a desktop app.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MeetingRush.LoopbackServer")
    // Accessed only on `queue`.
    private var started: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<String, Error>?
    private var pendingTarget: String?
    private var stopped = false

    init() throws {
        let parameters = NWParameters.tcp
        // Binding to loopback only keeps the port off the network and avoids a firewall prompt.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port the system assigned.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return continuation.resume(throwing: CancellationError()) }
                self.started = continuation
                self.listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(to: state) }
                self.listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                self.listener.start(queue: self.queue)
            }
        }
    }

    private func listenerChanged(to state: NWListener.State) {
        switch state {
        case .ready:
            started?.resume(returning: listener.port?.rawValue ?? 0)
        case .failed(let error):
            started?.resume(throwing: error)
        case .cancelled:
            started?.resume(throwing: CancellationError())
        default:
            return
        }
        started = nil
    }

    /// Waits for the request whose target carries the sign-in result, such as `/?code=…&state=…`.
    func waitForCallback() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let target = self.pendingTarget {
                    continuation.resume(returning: target)
                } else if self.stopped {
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.callback = continuation
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.listener.cancel()
            self.callback?.resume(throwing: CancellationError())
            self.callback = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first ?? ""
            let parts = requestLine.split(separator: " ")
            let target = parts.count >= 2 ? String(parts[1]) : ""
            let isCallback = target.contains("code=") || target.contains("error=")

            let body = isCallback ? Self.donePage : "Not found"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\n"
                + "Content-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })

            guard isCallback, pendingTarget == nil else { return }
            pendingTarget = target
            callback?.resume(returning: target)
            callback = nil
        }
    }

    private static let donePage = """
    <!doctype html><html><head><meta charset="utf-8"><title>MeetingRush</title></head>
    <body style="font: 15px -apple-system, sans-serif; text-align: center; padding-top: 20vh">
    <h2>You can close this tab.</h2><p>MeetingRush has finished signing in to Google.</p></body></html>
    """
}
