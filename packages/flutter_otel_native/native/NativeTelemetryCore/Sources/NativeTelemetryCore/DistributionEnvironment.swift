import Foundation

/// Determines which channel distributed the running app build, using the
/// same mechanism every major crash/telemetry SDK relies on: the presence
/// and filename of the app's StoreKit receipt
/// (`Bundle.main.appStoreReceiptURL`).
///
/// - `"testflight"`: a receipt URL exists and its filename is
///   `sandboxReceipt` (TestFlight and other sandbox-signed distributions).
/// - `"production"`: a receipt URL exists, isn't a sandbox receipt, and the
///   file is actually present on disk (a real App Store install).
/// - `"development"`: no receipt URL, or the file doesn't exist (an Xcode
///   debug/direct-install build never gets a receipt at all).
///
/// `appStoreReceiptURL` was deprecated in macOS 15/iOS 18 in favor of
/// StoreKit 2's `AppTransaction` — deliberately not migrated here: that API
/// is async, requires App Store Connect verification setup, and isn't
/// available on the older OS versions this SDK still supports, none of
/// which is worth the added complexity just to answer "which channel
/// installed this build."
public enum DistributionEnvironment {
    public static func current(
        receiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        guard let receiptURL else { return "development" }
        if receiptURL.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return fileExists(receiptURL.path) ? "production" : "development"
    }
}
