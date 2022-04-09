import fs from 'fs';
import hre from 'hardhat';

export interface StorageEntry {
  astId: number;
  contract: string;
  label: string;
  offset: number;
  slot: string;
  type: string;
}

export interface StorageType {
  base?: string;
  encoding: string;
  label: string;
  numberOfBytes: string;
}

export async function getStorageLayout(
  sourceName: string,
  contractName: string,
): Promise<{ storage: Array<StorageEntry>; types: { [typeName: string]: StorageType } }> {
  const paths = await hre.artifacts.getBuildInfoPaths();
  for (const path of paths) {
    const buildInfoData: Buffer = fs.readFileSync(path);
    const buildInfoJson = JSON.parse(buildInfoData.toString());

    if (
      buildInfoJson.output.contracts &&
      buildInfoJson.output.contracts[sourceName] &&
      buildInfoJson.output.contracts[sourceName][contractName] &&
      buildInfoJson.output.contracts[sourceName][contractName].storageLayout
    ) {
      return buildInfoJson.output.contracts[sourceName][contractName].storageLayout;
    }
  }

  throw new Error('Cannot find storage layout');
}

export function getEntryFromStorage(storage: StorageEntry[], label: string) {
  const entry = storage.find(s => s.label === label);
  if (entry === undefined) {
    throw new Error(`${label} not found in storage`);
  }
  return entry;
}

export function printStorage(storage: StorageEntry[]) {
  storage.forEach(s => {
    console.log(`${s.label} \t ${s.slot} ${s.offset} \t ${s.type}`);
  });
}
