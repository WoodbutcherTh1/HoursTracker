import Foundation
import Compression

enum ZipWriter {
    struct Entry {
        let path: String
        let data: Data
    }

    static func createArchive(entries: [Entry], outputURL: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let fileNameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let compressed = try deflate(entry.data)
            let uncompressedSize = UInt32(entry.data.count)
            let compressedSize = UInt32(compressed.count)

            var localHeader = Data()
            localHeader.appendUInt32(0x04034b50)
            localHeader.appendUInt16(20)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(8) // deflate
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(compressedSize)
            localHeader.appendUInt32(uncompressedSize)
            localHeader.appendUInt16(UInt16(fileNameData.count))
            localHeader.appendUInt16(0)
            localHeader.append(fileNameData)

            archive.append(localHeader)
            archive.append(compressed)

            var centralHeader = Data()
            centralHeader.appendUInt32(0x02014b50)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(8)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(crc)
            centralHeader.appendUInt32(compressedSize)
            centralHeader.appendUInt32(uncompressedSize)
            centralHeader.appendUInt16(UInt16(fileNameData.count))
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(0)
            centralHeader.appendUInt32(offset)
            centralHeader.append(fileNameData)

            centralDirectory.append(centralHeader)
            offset += UInt32(localHeader.count + compressed.count)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        var endRecord = Data()
        endRecord.appendUInt32(0x06054b50)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt32(UInt32(centralDirectory.count))
        endRecord.appendUInt32(centralOffset)
        endRecord.appendUInt16(0)

        archive.append(endRecord)
        try ProtectedFileWriter.shared.write(archive, to: outputURL)
    }

    /// Reads one entry written by `createArchive`. Used by tests (iOS has no `Process`/`unzip`).
    static func data(forEntry path: String, inArchiveAt url: URL) throws -> Data {
        try data(forEntry: path, in: Data(contentsOf: url))
    }

    static func data(forEntry path: String, in archive: Data) throws -> Data {
        let needle = Data(path.utf8)
        var offset = 0
        while offset + 30 <= archive.count {
            let signature = try archive.uint32LE(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else { throw ExportError.zipFailed }

            let compressionMethod = try archive.uint16LE(at: offset + 8)
            let compressedSize = Int(try archive.uint32LE(at: offset + 18))
            let uncompressedSize = Int(try archive.uint32LE(at: offset + 22))
            let fileNameLength = Int(try archive.uint16LE(at: offset + 26))
            let extraLength = Int(try archive.uint16LE(at: offset + 28))

            guard compressedSize >= 0, uncompressedSize >= 0,
                  fileNameLength >= 0, extraLength >= 0
            else { throw ExportError.zipFailed }

            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            guard nameEnd >= nameStart, nameEnd <= archive.count else {
                throw ExportError.zipFailed
            }
            let dataStart = nameEnd + extraLength
            guard dataStart >= nameEnd else { throw ExportError.zipFailed }
            let dataEnd = dataStart + compressedSize
            guard dataEnd >= dataStart, dataEnd <= archive.count else {
                throw ExportError.zipFailed
            }

            let name = archive.subdata(in: nameStart..<nameEnd)
            if name == needle {
                let payload = archive.subdata(in: dataStart..<dataEnd)
                switch compressionMethod {
                case 0:
                    return payload
                case 8:
                    return try inflate(payload, uncompressedSize: uncompressedSize)
                default:
                    throw ExportError.zipFailed
                }
            }
            offset = dataEnd
        }
        throw ExportError.zipFailed
    }

    private static func deflate(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        let destinationCapacity = data.count + 64
        var destination = Data(count: destinationCapacity)
        let compressedSize = destination.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_encode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    destinationCapacity,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard compressedSize > 0 else { throw ExportError.zipFailed }
        destination.count = compressedSize
        return destination
    }

    private static func inflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        if data.isEmpty { return Data() }
        let destinationCapacity = max(uncompressedSize, 1)
        var destination = Data(count: destinationCapacity)
        let decodedSize = destination.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    destinationCapacity,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize > 0 else { throw ExportError.zipFailed }
        destination.count = decodedSize
        return destination
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = (value >> 1) ^ 0xEDB8_8320
                } else {
                    value >>= 1
                }
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }

    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ExportError.zipFailed }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ExportError.zipFailed }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
