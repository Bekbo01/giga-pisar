// SHA-256 of a downloaded file, read in chunks so a 6 GB model never sits in memory.

import CryptoKit
import Foundation

func sha256Hex(ofFile path: String) -> String? {
    guard let h = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? h.close() }
    var hasher = SHA256()
    while true {
        let chunk = autoreleasepool { h.readData(ofLength: 4 << 20) }
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
