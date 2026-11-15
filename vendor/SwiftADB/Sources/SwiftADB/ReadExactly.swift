// SPDX-License-Identifier: BSD-3-Clause AND (GPL-3.0-or-later OR Apache-2.0)
// Extracted from upstream AdbConnection.swift; TCP segmentation handled explicitly.
import Foundation
import Network
extension NWConnection {
    func readExactly(count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: complete ? ADBError.connectionClosed : ADBError.incompleteRead) }
                }
            }
            result.append(chunk)
        }
        return result
    }
}
