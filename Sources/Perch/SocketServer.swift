import Foundation

final class SocketServer {
    typealias Handler = ([String: Any], @escaping ([String: Any]) -> Void) -> Void

    static var socketPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent.sock").path
    }

    private let path: String
    private let handler: Handler
    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.perch.socket", attributes: .concurrent)

    init(path: String = SocketServer.socketPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        unlink(path)

        listenerFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenerFD >= 0 else { throw SocketError.create }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try Self.copyPath(path, into: &addr)

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenerFD, $0, size)
            }
        }
        guard bound == 0, listen(listenerFD, 16) == 0 else {
            close(listenerFD)
            throw SocketError.bind
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let clientFD = accept(self.listenerFD, nil, nil)
            guard clientFD >= 0 else { return }
            self.queue.async { self.handleConnection(clientFD) }
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenerFD >= 0 { close(listenerFD) }
        unlink(path)
    }

    private func handleConnection(_ fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count < 1_048_576 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if buffer[..<n].contains(0x0A) { break }
        }

        guard
            let line = data.split(separator: 0x0A).first,
            let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        else {
            close(fd)
            return
        }

        // The connection stays open until the handler responds, which may be
        // long after this returns (e.g. waiting for an approval click)
        let responded = Atomic(false)
        handler(json) { response in
            guard !responded.getAndSet(true) else { return }
            if var out = try? JSONSerialization.data(withJSONObject: response) {
                out.append(0x0A)
                out.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
            }
            close(fd)
        }
    }

    static func copyPath(_ path: String, into addr: inout sockaddr_un) throws {
        let bytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= capacity else { throw SocketError.pathTooLong }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                bytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: src.count)
                }
            }
        }
    }

    enum SocketError: Error {
        case create, bind, pathTooLong
    }
}

final class Atomic<T> {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func getAndSet(_ newValue: T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
