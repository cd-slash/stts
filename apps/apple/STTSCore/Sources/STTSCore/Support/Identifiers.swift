import Foundation

/// Client-generated operation IDs used for protocol idempotency and correlation.
/// The protocol bounds identifiers to 1–200 characters; a UUID string fits.
public func newOperationId() -> String {
    UUID().uuidString
}
