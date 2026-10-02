import { registerPlugin } from '@capacitor/core';

import type { ICloudSyncPlugin } from './definitions';

const ICloudSync = registerPlugin<ICloudSyncPlugin>('ICloudSync', {
  web: () => import('./web').then((m) => new m.ICloudSyncWeb()),
});

export * from './definitions';
export { ICloudSync };
