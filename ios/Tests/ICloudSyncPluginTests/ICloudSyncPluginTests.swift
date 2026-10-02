import XCTest
@testable import ICloudSyncPlugin

class ICloudSyncPluginTests: XCTestCase {
    // CloudKit calls require a real device/simulator signed into iCloud and
    // a provisioned container, so there isn't a meaningful unit test to run
    // in CI here. This file exists so the SPM test target has something to
    // build; it's a placeholder for consumers who want to add their own
    // integration tests against a live CloudKit environment.
    func testPluginLoads() throws {
        XCTAssertNotNil(ICloudSyncPlugin())
    }
}
