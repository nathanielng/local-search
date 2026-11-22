import Foundation
import Darwin

/// What a running copy or move reports. Bytes are only counted for copies (a same-volume move is instant).
public struct TransferProgress: Sendable, Equatable {
    public var itemsDone: Int
    public var itemsTotal: Int
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var current: String
}

/// Copies files and folders with the system `copyfile`, keeping permissions, dates and extended attributes,
/// reporting bytes as they go and stopping part-way when asked.
public enum FileCopier {
    public struct Cancelled: Error {}

    final class Context {
        let cancel: CancelToken?
        let onBytes: @Sendable (Int64) -> Void
        var lastForFile: Int64 = 0
        var total: Int64 = 0
        init(cancel: CancelToken?, onBytes: @escaping @Sendable (Int64) -> Void) { self.cancel = cancel; self.onBytes = onBytes }
        func add(_ copied: Int64) {
            if copied < lastForFile { lastForFile = 0 }
            total += copied - lastForFile
            lastForFile = copied
            onBytes(total)
        }
    }

    /// Bytes in the regular files at or under `path` (links aren't followed).
    public static func byteCount(_ path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR { return (st.st_mode & S_IFMT) == S_IFREG ? Int64(st.st_size) : 0 }
        var sum: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { sum += Int64(v.fileSize ?? 0) }
        }
        return sum
    }

    private static let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
        guard let ctx else { return Int32(COPYFILE_CONTINUE) }
        let c = Unmanaged<Context>.fromOpaque(ctx).takeUnretainedValue()
        if c.cancel?.isCancelled == true { return Int32(COPYFILE_QUIT) }
        if what == COPYFILE_RECURSE_FILE && stage == COPYFILE_START { c.lastForFile = 0 }
        if what == COPYFILE_COPY_DATA && (stage == COPYFILE_PROGRESS || stage == COPYFILE_FINISH) {
            var copied: off_t = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 { c.add(Int64(copied)) }
        }
        return Int32(COPYFILE_CONTINUE)
    }

    /// Copy `src` (a file or folder) to the new path `dst`. `onBytes` gets the running total for this item.
    /// A partly written `dst` is removed if the copy fails or is stopped.
    /// `allowClone` lets APFS copy on the same volume instantly (no data moves, so no progress); tests turn it off.
    public static func copy(_ src: String, to dst: String, cancel: CancelToken? = nil, allowClone: Bool = true,
                            onBytes: @escaping @Sendable (Int64) -> Void = { _ in }) throws {
        let ctx = Context(cancel: cancel, onBytes: onBytes)
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let opaque = Unmanaged.passUnretained(ctx).toOpaque()
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), opaque)
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC | (allowClone ? COPYFILE_CLONE : 0))
        let rc = withExtendedLifetime(ctx) { copyfile(src, dst, state, flags) }
        if rc != 0 {
            let err = errno
            try? FileManager.default.removeItem(atPath: dst)
            if cancel?.isCancelled == true { throw Cancelled() }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))])
        }
        onBytes(ctx.total > 0 ? ctx.total : byteCount(dst))     // a clone moves no data, so report the full size
    }

    /// Move: a rename when on the same volume, otherwise copy with progress, then remove the original.
    public static func move(_ src: String, to dst: String, cancel: CancelToken? = nil,
                            onBytes: @escaping @Sendable (Int64) -> Void = { _ in }) throws {
        if rename(src, dst) == 0 { return }
        guard errno == EXDEV else {
            let err = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))])
        }
        try copy(src, to: dst, cancel: cancel, onBytes: onBytes)
        do { try FileManager.default.removeItem(atPath: src) }
        catch {   // the copy is complete but the original is stuck: keep both, say so
            throw NSError(domain: "FileCopier", code: 1, userInfo: [NSLocalizedDescriptionKey: "copied, but couldn't remove the original (\(error.localizedDescription))"])
        }
    }
}
