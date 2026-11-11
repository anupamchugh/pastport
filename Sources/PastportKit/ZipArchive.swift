import Compression
import Foundation

/// Limits for reading an archive the person chose. The archive is read in memory and never extracted.
public struct ZipLimits: Sendable, Equatable {
    public var maxArchiveBytes: Int
    public var maxUncompressedBytes: Int
    public var maxEntries: Int

    public init(maxArchiveBytes: Int, maxUncompressedBytes: Int, maxEntries: Int) {
        self.maxArchiveBytes = maxArchiveBytes
        self.maxUncompressedBytes = maxUncompressedBytes
        self.maxEntries = maxEntries
    }

    /// The Safari import limits from `docs/specs/2026-11-04-safari-history-import.md`.
    public static let safariExport = ZipLimits(
        maxArchiveBytes: 50 * 1024 * 1024,
        maxUncompressedBytes: 200 * 1024 * 1024,
        maxEntries: 10_000
    )
}

public enum ZipError: Error, Equatable {
    case tooLarge
    /// Not a ZIP, unsupported (ZIP64, split), or structurally inconsistent.
    case malformed
    /// Path traversal, absolute or duplicate paths, symlinks, or a size limit exceeded.
    case unsafe
    case encrypted
    case unsupportedCompression
}

/// A bounded, read-only view of a ZIP's central directory. Entry names are validated when the archive is
/// opened. An entry's bytes are inflated only when `data(for:)` is called for it, and never past its declared size.
public struct ZipArchive {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let isDirectory: Bool
        public let compressedSize: Int
        public let uncompressedSize: Int
        fileprivate let method: UInt16
        fileprivate let flags: UInt16
        fileprivate let localOffset: Int
    }

    public let entries: [Entry]
    private let bytes: Data

    /// Throws without returning a partial view: every failure is fail-closed.
    public init(bytes: Data, limits: ZipLimits = .safariExport) throws {
        guard bytes.count <= limits.maxArchiveBytes else { throw ZipError.tooLarge }
        self.bytes = bytes
        self.entries = try Self.readCentralDirectory(bytes, limits: limits)
    }

    /// Opens a security-scoped or ordinary file URL. The size is checked before any bytes are read and the
    /// file is memory-mapped, so the archive is not copied.
    public init(contentsOf url: URL, limits: ZipLimits = .safariExport) throws {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true else { throw ZipError.malformed }
        if let size = values?.fileSize, size > limits.maxArchiveBytes { throw ZipError.tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw ZipError.malformed }
        try self.init(bytes: data, limits: limits)
    }

    public func data(for entry: Entry) throws -> Data {
        guard !entry.isDirectory else { throw ZipError.malformed }
        guard entry.flags & 0x0001 == 0, entry.flags & 0x0040 == 0 else { throw ZipError.encrypted }
        let local = entry.localOffset
        guard bytes.u32(local) == 0x0403_4B50,
              let nameLength = bytes.u16(local + 26), let extraLength = bytes.u16(local + 28) else {
            throw ZipError.malformed
        }
        // The local header must describe the same file as the central directory.
        guard let localName = bytes.slice(local + 30, Int(nameLength)),
              String(bytes: localName, encoding: .utf8) == entry.name else { throw ZipError.malformed }
        let start = local + 30 + Int(nameLength) + Int(extraLength)
        guard let stored = bytes.slice(start, entry.compressedSize) else { throw ZipError.malformed }
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw ZipError.malformed }
            return Data(stored)
        case 8:
            return try Self.inflate(stored, expected: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression
        }
    }

    // MARK: Central directory

    private static func readCentralDirectory(_ bytes: Data, limits: ZipLimits) throws -> [Entry] {
        guard bytes.count >= 22 else { throw ZipError.malformed }
        // The end-of-central-directory record is within the last 22 + 65,535 bytes.
        let earliest = max(0, bytes.count - 22 - 65_535)
        var eocd: Int?
        var index = bytes.count - 22
        while index >= earliest {
            if bytes.u32(index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard let eocd, let diskNumber = bytes.u16(eocd + 4), let cdDisk = bytes.u16(eocd + 6),
              let onDisk = bytes.u16(eocd + 8), let total = bytes.u16(eocd + 10),
              let cdSize = bytes.u32(eocd + 12), let cdOffset = bytes.u32(eocd + 16) else {
            throw ZipError.malformed
        }
        // Split archives and ZIP64 are not Safari's format.
        guard diskNumber == 0, cdDisk == 0, onDisk == total, total != 0xFFFF, cdSize != 0xFFFF_FFFF,
              cdOffset != 0xFFFF_FFFF else { throw ZipError.malformed }
        guard Int(total) <= limits.maxEntries else { throw ZipError.unsafe }
        let directoryEnd = Int(cdOffset) + Int(cdSize)
        guard directoryEnd <= eocd else { throw ZipError.malformed }

        var entries: [Entry] = []
        entries.reserveCapacity(Int(total))
        var seen = Set<String>()
        var declaredTotal = 0
        var cursor = Int(cdOffset)
        for _ in 0..<Int(total) {
            guard bytes.u32(cursor) == 0x0201_4B50,
                  let madeBy = bytes.u16(cursor + 4), let flags = bytes.u16(cursor + 8),
                  let method = bytes.u16(cursor + 10), let compressed = bytes.u32(cursor + 20),
                  let uncompressed = bytes.u32(cursor + 24), let nameLength = bytes.u16(cursor + 28),
                  let extraLength = bytes.u16(cursor + 30), let commentLength = bytes.u16(cursor + 32),
                  let external = bytes.u32(cursor + 38), let localOffset = bytes.u32(cursor + 42),
                  let nameBytes = bytes.slice(cursor + 46, Int(nameLength)) else {
                throw ZipError.malformed
            }
            cursor += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard cursor <= directoryEnd else { throw ZipError.malformed }
            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
                throw ZipError.malformed
            }
            guard let name = String(bytes: nameBytes, encoding: .utf8), isSafe(name) else { throw ZipError.unsafe }
            let isUnix = (madeBy >> 8) == 3
            let mode = (external >> 16) & 0o170000
            // A symlink or any special file is never something this reader follows.
            if isUnix, mode != 0, mode != 0o100000, mode != 0o040000 { throw ZipError.unsafe }
            guard seen.insert(name.lowercased()).inserted else { throw ZipError.unsafe }
            declaredTotal += Int(uncompressed)
            guard declaredTotal <= limits.maxUncompressedBytes else { throw ZipError.unsafe }
            guard Int(localOffset) + 30 <= Int(cdOffset) else { throw ZipError.malformed }
            entries.append(Entry(
                name: name, isDirectory: name.hasSuffix("/"),
                compressedSize: Int(compressed), uncompressedSize: Int(uncompressed),
                method: method, flags: flags, localOffset: Int(localOffset)
            ))
        }
        return entries
    }

    /// Relative, no traversal, no backslashes, no control characters.
    static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 1024, !name.hasPrefix("/"), !name.contains("\\") else { return false }
        guard !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        let checked = name.hasSuffix("/") ? parts.dropLast() : parts[...]
        return !checked.contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }

    // MARK: Inflate

    /// Raw DEFLATE into a buffer one byte larger than declared, so an entry that inflates past its
    /// declared size is detected without holding more than that size in memory.
    private static func inflate(_ input: Data, expected: Int) throws -> Data {
        guard expected > 0 else { return Data() }
        let capacity = expected + 1
        var output = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity, src, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { throw ZipError.malformed }
        output.removeLast()
        return output
    }
}

private extension Data {
    func slice(_ offset: Int, _ length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else { return nil }
        return self[(startIndex + offset)..<(startIndex + offset + length)]
    }

    func u16(_ offset: Int) -> UInt16? {
        guard let s = slice(offset, 2) else { return nil }
        return UInt16(s[s.startIndex]) | UInt16(s[s.startIndex + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32? {
        guard let s = slice(offset, 4) else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(s[s.startIndex + $1]) << (8 * UInt32($1)) }
    }
}
