# capacitor-icloud-sync

Silent, automatic iCloud backup for Capacitor apps. No sign-in screen, no account creation — it just uses whatever iCloud account is already signed into the device, scoped automatically to that account via CloudKit's private database.

Built for apps that already have their own cloud save system (Firebase, Supabase, a custom backend, whatever) and want to offer iCloud as a second, independent, zero-friction backup option — not a replacement for an existing account system, just a parallel one.

iOS only. There is no CloudKit equivalent on Android or web; the web implementation resolves gracefully (`isAvailable()` reports `unsupported`, `loadData()` reports nothing found) so an app can call these methods on any platform without branching on `Capacitor.getPlatform()` everywhere, but `saveData()` throws on web since silently discarding a save would be a worse surprise than a clear error.

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

// Save your app's data — pass your own serialized save data
await ICloudSync.saveData({ json: JSON.stringify(mySaveData) });

// Load it back (e.g. on a fresh install, or a "Restore" button)
const { found, json } = await ICloudSync.loadData();
if (found) {
  const mySaveData = JSON.parse(json!);
  // ...apply it
}
```

Each `saveData()` call overwrites the previous backup — this plugin stores one record, not a history. Send your complete save data each time, not a partial diff.

## API

<docgen-index>

* [`isAvailable()`](#isavailable)
* [`saveData(...)`](#savedata)
* [`loadData()`](#loaddata)

</docgen-index>

<docgen-api>

### isAvailable()

```ts
isAvailable() => Promise<ICloudAvailability>
```

Checks whether iCloud is available and signed in on this device. Always resolves — never rejects — even when iCloud isn't available; check the `available` field on the result.

**Returns:** <code>Promise&lt;{ available: boolean; status: string; }&gt;</code>

---

### saveData(...)

```ts
saveData(options: ICloudSaveOptions) => Promise<void>
```

Saves a JSON string to a single record in the user's private CloudKit database. Overwrites any previous backup.

| Param         | Type                                                    |
| ------------- | -------------------------------------------------------- |
| **`options`** | <code>{ json: string; }</code>                          |

---

### loadData()

```ts
loadData() => Promise<ICloudLoadResult>
```

Loads the most recently saved backup, if one exists.

**Returns:** <code>Promise&lt;{ found: boolean; json?: string; }&gt;</code>

</docgen-api>

## Why not CloudKit's public database, or a more structured record schema?

Kept deliberately simple: one record, one field, in the *private* database (never visible to other users or Apple review — private CloudKit data is end-to-end encrypted per-account). If your app needs multiple named backups, per-character records, or querying, this plugin isn't the right fit as-is — fork it, the whole point of a small plugin like this is that it's easy to adapt.

## License

MIT
