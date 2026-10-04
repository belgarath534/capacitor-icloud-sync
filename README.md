# capacitor-icloud-sync

Silent, automatic iCloud backup for Capacitor apps. No sign-in screen, no account creation — it just uses whatever iCloud account is already signed into the device, scoped automatically to that account via CloudKit's private database.

Built for apps that already have their own cloud save system (Firebase, Supabase, a custom backend, whatever) and want to offer iCloud as a second, independent, zero-friction backup option — not a replacement for an existing account system, just a parallel one.

iOS only. There is no CloudKit equivalent on Android or web; the web implementation resolves gracefully (`isAvailable()` reports `unsupported`, `loadData()` reports nothing found) so an app can call these methods on any platform without branching on `Capacitor.getPlatform()` everywhere (`getInfo()` also reports nothing found, and `deleteData()` does nothing), but `saveData()` throws on web since silently discarding a save would be a worse surprise than a clear error.

## Install

```bash
npm install capacitor-icloud-sync
npx cap sync
```

## iOS setup (required before this will work)

This plugin cannot be provisioned on a free/personal-team Apple ID — it needs an active Apple Developer Program membership.

1. In Xcode, select your app target → **Signing & Capabilities** → **+ Capability** → **iCloud**. Check **CloudKit** and let Xcode create a default container (or pick an existing one).
2. Confirm your `App.entitlements` file now has:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
     <string>iCloud.your.bundle.id</string>
   </array>
   <key>com.apple.developer.icloud-services</key>
   <array>
     <string>CloudKit</string>
   </array>
   ```
3. Build and run on a real device (the simulator's iCloud support is unreliable) signed into a real iCloud account in Settings.

## Usage

```ts
import { ICloudSync } from 'capacitor-icloud-sync';

// Check availability before offering the feature in your UI
const { available } = await ICloudSync.isAvailable();

// Save your app's data — pass your complete serialized save data
const result = await ICloudSync.saveData({ json: JSON.stringify(mySaveData) });
// result: { savedAt, size, storedSize, encoding, asAsset }

// Before restoring, check whether iCloud is newer than what's on the device
// (this only downloads the date and size, never the save itself)
const info = await ICloudSync.getInfo();
if (info.found && info.updatedAt! > myLocalSaveTime) {
  const { json } = await ICloudSync.loadData();
  const mySaveData = JSON.parse(json!);
  // ...apply it
}

// "Reset all progress"
await ICloudSync.deleteData();
```

### Big saves

There is no practical size limit. CloudKit caps a single record at 1 MB, so the plugin:

1. Compresses the JSON first (on by default, usually 5 to 10 times smaller). Turn it off with `compress: false`.
2. Stores it inside the record when it fits.
3. Otherwise uploads it as a file attachment (a `CKAsset`) automatically. `saveData()` reports `asAsset: true` when that happens.

Your app code is the same either way. Backups count against the user's own iCloud storage; if it is full, `saveData()` rejects with the code `QUOTA_EXCEEDED`.

### More than one backup

Every method takes an optional `key` (default `save`), so an app can keep separate slots:

```ts
await ICloudSync.saveData({ key: 'settings', json: JSON.stringify(settings) });
await ICloudSync.saveData({ key: 'slot-2', json: JSON.stringify(secondSave) });
const settings = await ICloudSync.loadData({ key: 'settings' });
```

Keys use letters, numbers, dots, dashes and underscores, up to 200 characters.

### Errors

Rejections carry a `code` you can check:

| Code | Meaning |
| --- | --- |
| `NOT_SIGNED_IN` | No iCloud account on the device |
| `QUOTA_EXCEEDED` | The user's iCloud storage is full |
| `NETWORK` | No connection |
| `RETRY_LATER` | iCloud is busy (already retried twice for you) |
| `PERMISSION` | iCloud refused access |
| `TOO_LARGE` | The backup could not be uploaded because of its size |
| `NOT_CONFIGURED` | The iCloud capability or container is missing |
| `CORRUPT_DATA` | The backup exists but could not be read |
| `INVALID_ARGUMENT` | Missing `json` or a bad `key` |
| `ICLOUD_ERROR` | Anything else |

```ts
try {
  await ICloudSync.saveData({ json });
} catch (e: any) {
  if (e.code === 'QUOTA_EXCEEDED') showMessage('Your iCloud storage is full.');
}
```

### Account changes

```ts
ICloudSync.addListener('accountChanged', ({ available, status }) => {
  // the user signed in to or out of iCloud while the app was open
});
```

### Custom container

```ts
await ICloudSync.configure({ containerIdentifier: 'iCloud.com.example.shared' });
```

## API

| Method | Returns |
| --- | --- |
| `isAvailable()` | `{ available, status }`. Never rejects. |
| `configure({ containerIdentifier? })` | Use a specific iCloud container. |
| `saveData({ json, key?, compress? })` | `{ savedAt, size, storedSize, encoding, asAsset }` |
| `loadData({ key? })` | `{ found, json?, updatedAt?, size? }` |
| `getInfo({ key? })` | `{ found, updatedAt?, size?, encoding? }` without downloading the save |
| `deleteData({ key? })` | Resolves even if nothing was there |
| `addListener('accountChanged', fn)` | Fires when the iCloud account changes |

Times are in milliseconds since 1970, like `Date.now()`.

## Upgrading from 0.1.x

Nothing to change in your code. `saveData()` now resolves with details instead of nothing, and backups made by 0.1.x still load: they live in the default `save` slot. The first save with 0.2 rewrites the record in the new format.

## Why the private database, and one record per slot?

Private CloudKit data is never visible to other users or to Apple review, and it is end-to-end encrypted per account. Keeping one record per slot makes the plugin small and predictable. If your app needs querying or sharing between users, this plugin isn't the right fit as-is; fork it, the whole point of a small plugin like this is that it's easy to adapt.

## License

MIT
