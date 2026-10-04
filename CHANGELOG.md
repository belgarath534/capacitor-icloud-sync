# Changelog

## 0.2.0

- Saves of any size: data over CloudKit's 1 MB record limit is uploaded as a file attachment automatically.
- Compression before upload, on by default (`compress: false` to turn it off).
- `saveData()` resolves with `{ savedAt, size, storedSize, encoding, asAsset }`.
- `loadData()` also returns `updatedAt` and `size`.
- New `getInfo()`: the date and size of a backup, without downloading it.
- New `deleteData()`.
- New `configure({ containerIdentifier })` for a custom iCloud container.
- Named slots with the `key` option (default `save`, the slot 0.1.x used).
- Saves overwrite in one step, which fixes a rare "record changed" error when the first fetch failed.
- Temporary iCloud errors are retried automatically, and every rejection has a `code` such as `QUOTA_EXCEEDED` or `NOT_SIGNED_IN`.
- New `accountChanged` event.
- Backups made by 0.1.x still load.

## 0.1.0

- First release: `isAvailable()`, `saveData()`, `loadData()`.
