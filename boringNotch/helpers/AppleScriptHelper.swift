//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

final class AppleScriptHelper {
    /// NSAppleScript isn't safe to use from several threads at once, and
    /// scripts start from many places (media controllers, the playback
    /// handoff), so they run one at a time.
    private static let queue = DispatchQueue(label: "boringNotch.AppleScript", qos: .userInitiated)

    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }

    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
