import type { PluginListenerHandle } from '@capacitor/core';

export interface ICloudAvailability {
  /** Whether iCloud is currently available and signed in on this device. */
  available: boolean;
  /**
   * Raw account status string, for diagnostics.
   * One of: 'available' | 'noAccount' | 'restricted' | 'couldNotDetermine' | 'temporarilyUnavailable' | 'unsupported' | 'unknown'.
   */
  status: string;
}

export interface ICloudConfigureOptions {
  /**
   * The iCloud container to use, like `iCloud.com.example.app`.
   * Leave it out to use the app's default container.
   */
  containerIdentifier?: string;
}

export interface ICloudKeyOptions {
  /**
   * Which backup slot to use. Letters, numbers, dots, dashes and
   * underscores, up to 200 characters. Defaults to `save`, the only
   * slot 0.1.x used, so older backups keep working.
   */
  key?: string;
}

export interface ICloudSaveOptions extends ICloudKeyOptions {
  /** The data to back up, as a JSON string. */
  json: string;
  /**
   * Compress the data before uploading. On by default: JSON usually
   * shrinks 5 to 10 times, which makes saves faster and uses less of
   * the user's iCloud storage.
   */
  compress?: boolean;
}

export interface ICloudSaveResult {
  /** When the backup was saved, in milliseconds since 1970. */
  savedAt: number;
  /** Size of the JSON you passed in, in bytes. */
  size: number;
  /** Size actually uploaded, after compression, in bytes. */
  storedSize: number;
  /** 'zlib' when the data was compressed, 'raw' otherwise. */
  encoding: 'zlib' | 'raw';
  /**
   * True when the backup was too big to fit inside the record (CloudKit
   * caps a record at 1 MB) and was uploaded as a file attachment instead.
   */
  asAsset: boolean;
}

export interface ICloudLoadResult {
  /** Whether a previously-saved backup was found. */
  found: boolean;
  /** The backed-up data, as a JSON string. Only present when `found` is true. */
  json?: string;
  /** When the backup was saved, in milliseconds since 1970. */
  updatedAt?: number;
  /** Size of the backed-up JSON, in bytes (not reported for 0.1.x backups). */
  size?: number;
}

export interface ICloudInfoResult {
  /** Whether a backup exists in this slot. */
  found: boolean;
  /** When the backup was saved, in milliseconds since 1970. */
  updatedAt?: number;
  /** Size of the backed-up JSON, in bytes. */
  size?: number;
  /** 'zlib' or 'raw'. */
  encoding?: string;
}

export interface ICloudAccountChange {
  available: boolean;
  status: string;
}

/**
 * Errors are rejected with one of these `code` values, so you can react
 * to them (for example, tell the user their iCloud storage is full):
 * 'NOT_SIGNED_IN' | 'QUOTA_EXCEEDED' | 'NETWORK' | 'RETRY_LATER' | 'PERMISSION' |
 * 'TOO_LARGE' | 'NOT_CONFIGURED' | 'CORRUPT_DATA' | 'INVALID_ARGUMENT' | 'ICLOUD_ERROR'.
 * Temporary errors (iCloud busy, rate limited, a network blip) are already
 * retried twice before you see them.
 */
export type ICloudErrorCode =
  | 'NOT_SIGNED_IN'
  | 'QUOTA_EXCEEDED'
  | 'NETWORK'
  | 'RETRY_LATER'
  | 'PERMISSION'
  | 'TOO_LARGE'
  | 'NOT_CONFIGURED'
  | 'CORRUPT_DATA'
  | 'INVALID_ARGUMENT'
  | 'ICLOUD_ERROR';

export interface ICloudSyncPlugin {
  /**
   * Checks whether iCloud is available and signed in on this device.
   * Always resolves — never rejects — even when iCloud isn't available;
   * check the `available` field on the result.
   */
  isAvailable(): Promise<ICloudAvailability>;

  /**
   * Optional. Use a specific iCloud container instead of the app's default one.
   */
  configure(options: ICloudConfigureOptions): Promise<void>;

  /**
   * Saves a JSON string to the user's private CloudKit database, replacing
   * whatever was in that slot. Send your complete save data each time, not
   * a partial diff. Any size works: big saves go up as a file attachment
   * automatically.
   */
  saveData(options: ICloudSaveOptions): Promise<ICloudSaveResult>;

  /**
   * Loads a backup, if one exists.
   */
  loadData(options?: ICloudKeyOptions): Promise<ICloudLoadResult>;

  /**
   * Tells you if a backup exists, when it was saved and how big it is,
   * without downloading it. Use it to decide whether the iCloud copy is
   * newer than the one on the device before restoring.
   */
  getInfo(options?: ICloudKeyOptions): Promise<ICloudInfoResult>;

  /**
   * Deletes a backup. Resolves even if there was nothing to delete.
   */
  deleteData(options?: ICloudKeyOptions): Promise<void>;

  /**
   * Fires when the user signs in to or out of iCloud while the app is running.
   */
  addListener(eventName: 'accountChanged', listenerFunc: (change: ICloudAccountChange) => void): Promise<PluginListenerHandle>;

  /**
   * Removes all listeners for this plugin.
   */
  removeAllListeners(): Promise<void>;
}
