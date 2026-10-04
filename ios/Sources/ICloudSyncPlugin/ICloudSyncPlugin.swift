import Foundation
import Capacitor
import CloudKit

/**
 * A silent, automatic backup destination — no sign-in screen, no account
 * creation. It just uses whatever iCloud account is already signed into
 * the device. Each backup is one CKRecord in the user's PRIVATE CloudKit
 * database, which CloudKit already scopes per-iCloud-account on its own,
 * so there's no separate user-identity handling to build.
 *
 * Record layout (record type "PluginSaveData", record name = the backup key):
 * - payload:   Data, the save (zlib-compressed when that makes it smaller)
 *              when it fits inline; CloudKit caps a whole record at 1 MB.
 * - asset:     CKAsset, used instead of `payload` for larger saves.
 * - encoding:  "zlib" or "raw".
 * - size:      Int, the uncompressed size in bytes.
 * - updatedAt: Date of the save.
 * - json:      String, written only by 0.1.x; still read for compatibility.
 *
 * Requirements for consuming apps:
 * - Add the iCloud capability in Xcode (Signing & Capabilities), with
 *   CloudKit enabled and a default container (or call configure()).
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
        CAPPluginMethod(name: "configure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteData", returnType: CAPPluginReturnPromise)
    ]

    private let recordType = "PluginSaveData"
    private let defaultKey = "save"
    // Leave headroom under CloudKit's 1 MB record limit for the other fields.
    private let inlineLimit = 900_000
    private let maxRetries = 2
    private var containerIdentifier: String?

    private var container: CKContainer {
        if let id = containerIdentifier {
            return CKContainer(identifier: id)
        }
        return CKContainer.default()
    }

    private var privateDatabase: CKDatabase {
        return container.privateCloudDatabase
    }

    override public func load() {
        NotificationCenter.default.addObserver(self, selector: #selector(accountDidChange), name: .CKAccountChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accountDidChange() {
        container.accountStatus { status, _ in
            self.notifyListeners("accountChanged", data: ["available": status == .available, "status": self.statusString(status)])
        }
    }

    // MARK: - Availability and setup

    @objc func isAvailable(_ call: CAPPluginCall) {
        container.accountStatus { status, error in
            if let error = error {
                call.resolve(["available": false, "status": "couldNotDetermine", "error": error.localizedDescription])
                return
            }
            call.resolve(["available": status == .available, "status": self.statusString(status)])
        }
    }

    @objc func configure(_ call: CAPPluginCall) {
        if let id = call.getString("containerIdentifier"), !id.isEmpty {
            containerIdentifier = id
        } else {
            containerIdentifier = nil
        }
        call.resolve()
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

    // MARK: - Save

    @objc func saveData(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing json string", "INVALID_ARGUMENT")
            return
        }
        guard let recordID = recordID(for: call) else {
            call.reject("Invalid key. Use 1 to 200 letters, numbers, dots, dashes or underscores.", "INVALID_ARGUMENT")
            return
        }
        let raw = Data(json.utf8)
        var payload = raw
        var encoding = "raw"
        if call.getBool("compress") ?? true,
           let packed = try? (raw as NSData).compressed(using: .zlib) as Data,
           packed.count < raw.count {
            payload = packed
            encoding = "zlib"
        }
        save(call, recordID: recordID, payload: payload, encoding: encoding, originalSize: raw.count, attempt: 0)
    }

    private func save(_ call: CAPPluginCall, recordID: CKRecord.ID, payload: Data, encoding: String, originalSize: Int, attempt: Int) {
        let now = Date()
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["encoding"] = encoding as NSString
        record["size"] = NSNumber(value: originalSize)
        record["updatedAt"] = now as NSDate

        var tempURL: URL?
        if payload.count <= inlineLimit {
            record["payload"] = payload as NSData
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-sync-\(UUID().uuidString).bin")
            do {
                try payload.write(to: url, options: .atomic)
            } catch {
                call.reject("Could not prepare the backup file: \(error.localizedDescription)", "ICLOUD_ERROR", error)
                return
            }
            tempURL = url
            record["asset"] = CKAsset(fileURL: url)
        }

        // .allKeys overwrites whatever is on the server in one step, so there's
        // no fetch-then-save race and no "record changed" conflict to handle.
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated
        operation.modifyRecordsCompletionBlock = { _, _, error in
            if let url = tempURL {
                try? FileManager.default.removeItem(at: url)
            }
            if let error = self.itemError(error, for: recordID) {
                if let delay = self.retryDelay(error), attempt < self.maxRetries {
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.save(call, recordID: recordID, payload: payload, encoding: encoding, originalSize: originalSize, attempt: attempt + 1)
                    }
                    return
                }
                self.reject(call, error, action: "save")
                return
            }
            call.resolve([
                "savedAt": now.timeIntervalSince1970 * 1000,
                "size": originalSize,
                "storedSize": payload.count,
                "encoding": encoding,
                "asAsset": tempURL != nil
            ])
        }
        privateDatabase.add(operation)
    }

    // MARK: - Load, info, delete

    @objc func loadData(_ call: CAPPluginCall) {
        guard let recordID = recordID(for: call) else {
            call.reject("Invalid key. Use 1 to 200 letters, numbers, dots, dashes or underscores.", "INVALID_ARGUMENT")
            return
        }
        fetch(recordID, desiredKeys: nil, attempt: 0) { record, error in
            if let error = error {
                if self.isMissing(error) {
                    call.resolve(["found": false])
                } else {
                    self.reject(call, error, action: "load")
                }
                return
            }
            guard let record = record else {
                call.resolve(["found": false])
                return
            }
            do {
                guard let json = try self.decode(record) else {
                    call.resolve(["found": false])
                    return
                }
                var result: [String: Any] = ["found": true, "json": json]
                self.addMetadata(record, to: &result)
                call.resolve(result)
            } catch {
                call.reject("The iCloud backup could not be read: \(error.localizedDescription)", "CORRUPT_DATA", error)
            }
        }
    }

    @objc func getInfo(_ call: CAPPluginCall) {
        guard let recordID = recordID(for: call) else {
            call.reject("Invalid key. Use 1 to 200 letters, numbers, dots, dashes or underscores.", "INVALID_ARGUMENT")
            return
        }
        // Only the small fields: the save itself is never downloaded here.
        fetch(recordID, desiredKeys: ["updatedAt", "size", "encoding"], attempt: 0) { record, error in
            if let error = error {
                if self.isMissing(error) {
                    call.resolve(["found": false])
                } else {
                    self.reject(call, error, action: "check")
                }
                return
            }
            guard let record = record else {
                call.resolve(["found": false])
                return
            }
            var result: [String: Any] = ["found": true]
            self.addMetadata(record, to: &result)
            call.resolve(result)
        }
    }

    @objc func deleteData(_ call: CAPPluginCall) {
        guard let recordID = recordID(for: call) else {
            call.reject("Invalid key. Use 1 to 200 letters, numbers, dots, dashes or underscores.", "INVALID_ARGUMENT")
            return
        }
        delete(call, recordID: recordID, attempt: 0)
    }

    private func delete(_ call: CAPPluginCall, recordID: CKRecord.ID, attempt: Int) {
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        operation.qualityOfService = .userInitiated
        operation.modifyRecordsCompletionBlock = { _, _, error in
            if let error = self.itemError(error, for: recordID), !self.isMissing(error) {
                if let delay = self.retryDelay(error), attempt < self.maxRetries {
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.delete(call, recordID: recordID, attempt: attempt + 1)
                    }
                    return
                }
                self.reject(call, error, action: "delete")
                return
            }
            call.resolve()
        }
        privateDatabase.add(operation)
    }

    private func fetch(_ recordID: CKRecord.ID, desiredKeys: [CKRecord.FieldKey]?, attempt: Int, completion: @escaping (CKRecord?, Error?) -> Void) {
        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        operation.desiredKeys = desiredKeys
        operation.qualityOfService = .userInitiated
        operation.fetchRecordsCompletionBlock = { records, error in
            if let record = records?[recordID] {
                completion(record, nil)
                return
            }
            let error = self.itemError(error, for: recordID)
            if let error = error, let delay = self.retryDelay(error), attempt < self.maxRetries {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.fetch(recordID, desiredKeys: desiredKeys, attempt: attempt + 1, completion: completion)
                }
                return
            }
            completion(nil, error)
        }
        privateDatabase.add(operation)
    }

    // MARK: - Helpers

    private func recordID(for call: CAPPluginCall) -> CKRecord.ID? {
        let key = call.getString("key") ?? defaultKey
        guard key.count >= 1, key.count <= 200,
              key.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return CKRecord.ID(recordName: key)
    }

    private func decode(_ record: CKRecord) throws -> String? {
        var data: Data?
        if let inline = record["payload"] as? Data {
            data = inline
        } else if let asset = record["asset"] as? CKAsset, let url = asset.fileURL {
            data = try Data(contentsOf: url)
        }
        guard var bytes = data else {
            // A backup written by version 0.1.x.
            return record["json"] as? String
        }
        if (record["encoding"] as? String) == "zlib" {
            bytes = try (bytes as NSData).decompressed(using: .zlib) as Data
        }
        return String(data: bytes, encoding: .utf8)
    }

    private func addMetadata(_ record: CKRecord, to result: inout [String: Any]) {
        if let date = record["updatedAt"] as? Date {
            result["updatedAt"] = date.timeIntervalSince1970 * 1000
        } else if let date = record.modificationDate {
            result["updatedAt"] = date.timeIntervalSince1970 * 1000
        }
        if let size = record["size"] as? Int {
            result["size"] = size
        }
        if let encoding = record["encoding"] as? String {
            result["encoding"] = encoding
        }
    }

    /// Unwraps a partial failure into the error for our one record.
    private func itemError(_ error: Error?, for recordID: CKRecord.ID) -> Error? {
        guard let error = error else { return nil }
        if let ckError = error as? CKError, ckError.code == .partialFailure,
           let inner = ckError.partialErrorsByItemID?[recordID] {
            return inner
        }
        return error
    }

    private func isMissing(_ error: Error) -> Bool {
        return (error as? CKError)?.code == .unknownItem
    }

    /// How long to wait before retrying, or nil if the error is not worth retrying.
    private func retryDelay(_ error: Error) -> TimeInterval? {
        guard let ckError = error as? CKError else { return nil }
        let retryable: [CKError.Code] = [.serviceUnavailable, .requestRateLimited, .zoneBusy, .networkFailure]
        guard retryable.contains(ckError.code) else { return nil }
        return ckError.retryAfterSeconds ?? 2
    }

    private func reject(_ call: CAPPluginCall, _ error: Error, action: String) {
        let message = "iCloud \(action) failed: \(error.localizedDescription)"
        guard let ckError = error as? CKError else {
            call.reject(message, "ICLOUD_ERROR", error)
            return
        }
        let code: String
        switch ckError.code {
        case .notAuthenticated: code = "NOT_SIGNED_IN"
        case .quotaExceeded: code = "QUOTA_EXCEEDED"
        case .networkUnavailable, .networkFailure: code = "NETWORK"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: code = "RETRY_LATER"
        case .permissionFailure: code = "PERMISSION"
        case .limitExceeded, .assetFileNotFound: code = "TOO_LARGE"
        case .badContainer, .missingEntitlement: code = "NOT_CONFIGURED"
        default: code = "ICLOUD_ERROR"
        }
        var data: [String: Any] = ["ckErrorCode": ckError.code.rawValue]
        if let seconds = ckError.retryAfterSeconds {
            data["retryAfter"] = seconds
        }
        call.reject(message, code, error, data)
    }
}
