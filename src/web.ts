import { WebPlugin } from '@capacitor/core';

import type {
  ICloudAvailability,
  ICloudConfigureOptions,
  ICloudInfoResult,
  ICloudKeyOptions,
  ICloudLoadResult,
  ICloudSaveOptions,
  ICloudSaveResult,
  ICloudSyncPlugin,
} from './definitions';

// CloudKit is an iOS-only concept — there's no web equivalent, so this
// fallback reports unavailability rather than throwing on isAvailable()/
// loadData()/getInfo() (a caller checking availability first shouldn't need
// a try/catch just to run on web), but does throw on saveData() since
// silently discarding a save would be a worse surprise than a clear error.
export class ICloudSyncWeb extends WebPlugin implements ICloudSyncPlugin {
  async isAvailable(): Promise<ICloudAvailability> {
    return { available: false, status: 'unsupported' };
  }

  async configure(_options: ICloudConfigureOptions): Promise<void> {
    return;
  }

  async saveData(_options: ICloudSaveOptions): Promise<ICloudSaveResult> {
    throw this.unimplemented('iCloud sync is only available on iOS.');
  }

  async loadData(_options?: ICloudKeyOptions): Promise<ICloudLoadResult> {
    return { found: false };
  }

  async getInfo(_options?: ICloudKeyOptions): Promise<ICloudInfoResult> {
    return { found: false };
  }

  async deleteData(_options?: ICloudKeyOptions): Promise<void> {
    return;
  }
}
