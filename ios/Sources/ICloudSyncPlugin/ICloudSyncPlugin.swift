import Foundation
import Capacitor
import CloudKit

/**
 * A silent, automatic backup destination — no sign-in screen, no account
 * creation. It just uses whatever iCloud account is already signed into
 * the device. Save data goes into one CKRecord in the user's PRIVATE
 * CloudKit database, which CloudKit already scopes per-iCloud-account on
 * its own, so there's no separate user-identity handling to build.
 *
 * Requirements for consuming apps:
 * - Add the iCloud capability in Xcode (Signing & Capabilities), with
 *   CloudKit enabled and a default container.
 * - Add `com.apple.developer.icloud-container-identifiers` and
 *   `com.apple.developer.icloud-services` (CloudKit) to the app's
 *   entitlements file.
 * - Requires an active Apple Developer Program membership — the iCloud
 *   capability can't be provisioned on a free/personal-team account.
 */
@objc(ICloudSyncPlugin)
public class ICloudSyncPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ICloudSyncPlugin"
    public let jsName = "ICloudSync"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadData", returnType: CAPPluginReturnPromise)
    ]

    private let recordType = "PluginSaveData"
    private let recordName = "save"
    private let fieldName = "json"

    private var privateDatabase: CKDatabase {
        return CKContainer.default().privateCloudDatabase
    }

    private var recordID: CKRecord.ID {
        return CKRecord.ID(recordName: recordName)
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        CKContainer.default().accountStatus { status, error in
            if let error = error {
                call.resolve(["available": false, "status": "couldNotDetermine", "error": error.localizedDescription])
                return
            }
            call.resolve(["available": status == .available, "status": self.statusString(status)])
        }
    }

    private func statusString(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }

    @objc func saveData(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing json string")
            return
        }
        let database = privateDatabase
        let targetID = recordID
        database.fetch(withRecordID: targetID) { existingRecord, _ in
            // Any fetch error (including "not found") falls back to a
            // fresh record — a genuine network problem surfaces again on
            // the save call below, so it isn't swallowed silently.
            let record = existingRecord ?? CKRecord(recordType: self.recordType, recordID: targetID)
            record[self.fieldName] = json as CKRecordValue
            database.save(record) { _, saveError in
                if let saveError = saveError {
                    call.reject("iCloud save failed: \(saveError.localizedDescription)")
                    return
                }
                call.resolve()
            }
        }
    }

    @objc func loadData(_ call: CAPPluginCall) {
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    // No backup saved yet — not an error, just nothing there.
                    call.resolve(["found": false])
                    return
                }
                call.reject("iCloud load failed: \(error.localizedDescription)")
                return
            }
            guard let json = record?[self.fieldName] as? String else {
                call.resolve(["found": false])
                return
            }
            call.resolve(["found": true, "json": json])
        }
    }
}
