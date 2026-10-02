import { WebPlugin } from '@capacitor/core';

import type { ICloudAvailability, ICloudLoadResult, ICloudSaveOptions, ICloudSyncPlugin } from './definitions';

// CloudKit is an iOS-only concept — there's no web equivalent, so this
// fallback reports unavailability rather than throwing on isAvailable()/
// loadData() (a caller checking availability first shouldn't need a
// try/catch just to run on web), but does throw on saveData() since
// silently discarding a save would be a worse surprise than a clear error.
export class ICloudSyncWeb extends WebPlugin implements ICloudSyncPlugin {
  async isAvailable(): Promise<ICloudAvailability> {
    return { available: false, status: 'unsupported' };
  }

  async saveData(_options: ICloudSaveOptions): Promise<void> {
    throw this.unimplemented('iCloud sync is only available on iOS.');
  }

  async loadData(): Promise<ICloudLoadResult> {
    return { found: false };
  }
}
