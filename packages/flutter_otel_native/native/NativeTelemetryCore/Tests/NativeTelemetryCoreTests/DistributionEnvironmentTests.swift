@testable import NativeTelemetryCore
import XCTest

final class DistributionEnvironmentTests: XCTestCase {
    func testReturnsUnknownWhenNoReceiptURL() {
        let result = DistributionEnvironment.current(receiptURL: nil)

        XCTAssertEqual(result, "unknown")
    }

    func testReturnsTestflightForASandboxReceiptRegardlessOfFileExistence() {
        let url = URL(fileURLWithPath: "/private/var/mobile/sandboxReceipt")

        let result = DistributionEnvironment.current(
            receiptURL: url,
            fileExists: { _ in false }
        )

        XCTAssertEqual(result, "testflight")
    }

    func testReturnsProductionWhenANonSandboxReceiptFileExists() {
        let url = URL(fileURLWithPath: "/private/var/mobile/receipt")

        let result = DistributionEnvironment.current(
            receiptURL: url,
            fileExists: { _ in true }
        )

        XCTAssertEqual(result, "production")
    }

    func testReturnsUnknownWhenReceiptURLIsPresentButTheFileIsMissing() {
        let url = URL(fileURLWithPath: "/private/var/mobile/receipt")

        let result = DistributionEnvironment.current(
            receiptURL: url,
            fileExists: { _ in false }
        )

        XCTAssertEqual(result, "unknown")
    }
}
