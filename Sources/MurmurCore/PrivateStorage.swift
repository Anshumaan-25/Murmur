import Darwin
import Foundation

public enum PrivateStorage {
    public static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try existingDirectory(url)
    }

    static func existingDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try protect(fd, type: S_IFDIR, mode: 0o700)
    }

    static func file(_ url: URL, create: Bool = false) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (create ? O_CREAT : 0), 0o600)
        try protect(fd, type: S_IFREG, mode: 0o600)
    }

    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".keydown-write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw error() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close(); _ = unlink(temporary.path) }
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        guard rename(temporary.path, url.path) == 0 else { throw error() }
    }

    private static func protect(_ fd: Int32, type: mode_t, mode: mode_t) throws {
        guard fd >= 0 else { throw error() }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw error() }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == type, type != S_IFREG || info.st_nlink == 1 else {
            throw MurmurError.unavailable("Local storage is not a private file or directory.")
        }
        if info.st_mode & 0o7777 != mode, fchmod(fd, mode) != 0 { throw error() }
        if let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            if acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0, entry != nil {
                guard let empty = acl_init(0) else { throw error() }
                defer { acl_free(UnsafeMutableRawPointer(empty)) }
                guard acl_set_fd_np(fd, empty, ACL_TYPE_EXTENDED) == 0 else { throw error() }
            }
        }
    }

    static func error() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
