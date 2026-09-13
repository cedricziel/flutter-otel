import Foundation
#if canImport(Security)
    import Security
#endif

/// Generates W3C-Trace-Context-conformant IDs: a 32-lowercase-hex-character
/// trace ID (16 random bytes) and a 16-lowercase-hex-character span ID (8
/// random bytes) — exactly the format `SpanContext` on the Dart side
/// already validates, so no coordination between the two sides is needed.
public enum NativeId {
    public static func generateTraceId() -> String {
        hexString(byteCount: 16)
    }

    public static func generateSpanId() -> String {
        hexString(byteCount: 8)
    }

    private static func hexString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        #if canImport(Security)
            let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
            if status != errSecSuccess {
                for i in 0 ..< byteCount {
                    bytes[i] = UInt8.random(in: 0 ... 255)
                }
            }
        #else
            for i in 0 ..< byteCount {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        #endif
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
