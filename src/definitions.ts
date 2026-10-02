export interface ICloudAvailability {
  /** Whether iCloud is currently available and signed in on this device. */
  available: boolean;
  /**
   * Raw account status string, for diagnostics.
   * One of: 'available' | 'noAccount' | 'restricted' | 'couldNotDetermine' | 'temporarilyUnavailable' | 'unsupported' | 'unknown'.
   */
  status: string;
}

export interface ICloudSaveOptions {
  /** The data to back up, as a JSON string. */
  json: string;
}

export interface ICloudLoadResult {
  /** Whether a previously-saved backup was found. */
  found: boolean;
  /** The backed-up data, as a JSON string. Only present when `found` is true. */
  json?: string;
}

export interface ICloudSyncPlugin {
  /**
   * Checks whether iCloud is available and signed in on this device.
   * Always resolves — never rejects — even when iCloud isn't available;
   * check the `available` field on the result.
   */
  isAvailable(): Promise<ICloudAvailability>;

  /**
   * Saves a JSON string to a single record in the user's private CloudKit
   * database. Overwrites any previous backup. Each call replaces the whole
   * backup rather than merging — callers should send their complete save
   * data each time, not a partial diff.
   */
  saveData(options: ICloudSaveOptions): Promise<void>;

  /**
   * Loads the most recently saved backup, if one exists.
   */
  loadData(): Promise<ICloudLoadResult>;
}
