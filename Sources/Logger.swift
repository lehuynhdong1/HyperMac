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

    /// `/tmp` dùng chung cho mọi user: mở bằng `O_NOFOLLOW` (không đi theo symlink do user khác cài sẵn)
    /// và kiểm tra bằng `fstat` rằng đây là file thường thuộc user hiện tại; nếu không thì bỏ ghi log.
    static func openIfNeeded() {
        guard handle == nil else { return }
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              st.st_uid == getuid(),
              st.st_nlink == 1 else {
            close(fd)
            return
        }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        size = UInt64(max(0, st.st_size))
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
