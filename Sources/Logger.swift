import Foundation

/// Ghi log ra `/tmp/displaycontrol.log` trên một hàng đợi nền nối tiếp (không chặn main thread),
/// giữ một FileHandle mở thay vì mở/đóng file mỗi dòng, và tự xoay vòng khi file vượt 2 MB
/// (file cũ đổi tên thành `displaycontrol.log.1`, chỉ giữ 1 bản) để log không phình vô hạn.
private enum LogSink {
    static let path = "/tmp/displaycontrol.log"
    static let rotatedPath = "/tmp/displaycontrol.log.1"
    static let maxBytes: UInt64 = 2 * 1024 * 1024
    static let queue = DispatchQueue(label: "com.opensource.hypermac.log", qos: .utility)
    static var handle: FileHandle?
    static var size: UInt64 = 0
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func openIfNeeded() {
        guard handle == nil else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: path)
        size = (try? handle?.seekToEnd()) ?? 0
    }

    static func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(atPath: rotatedPath)
        try? fm.moveItem(atPath: path, toPath: rotatedPath)
        openIfNeeded()
    }

    static func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        openIfNeeded()
        if size + UInt64(data.count) > maxBytes {
            rotate()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += UInt64(data.count)
        } catch {
            // File bị xoá/thay từ bên ngoài → mở lại ở lần ghi sau.
            try? handle.close()
            self.handle = nil
        }
    }
}

public func appLog(_ message: String) {
    let date = Date()
    LogSink.queue.async {
        let line = "[\(LogSink.formatter.string(from: date))] \(message)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        LogSink.write(line)
    }
}
