// Where the server keeps its files (the leaderboard, the entries, the
// aliases, the session secret): a folder on a laptop (TATYX_DATA_DIR), an
// S3 bucket deployed (TATYX_DATA_BUCKET), under a prefix. A bucket is
// shared by every instance of the functions, so it is read anew each time;
// a folder belongs to one process, which may keep what it read.
// Never logs what it reads or writes.

import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

/** A folder: each name a file, written through a temporary file, mode 600. */
export function fileStore(dir) {
  return {
    shared: false,
    /** The file's text; null when there is none. */
    async read(name) {
      try {
        return await readFile(join(dir, name), 'utf8');
      } catch (error) {
        if (error?.code === 'ENOENT') return null;
        throw error;
      }
    },
    async write(name, text) {
      await mkdir(dir, { recursive: true });
      const file = join(dir, name);
      const temp = `${file}.tmp`;
      await writeFile(temp, text, { mode: 0o600 });
      await rename(temp, file);
    },
    /** Writes the file only if there is none yet; false when there was one. */
    async create(name, text) {
      await mkdir(dir, { recursive: true });
      try {
        await writeFile(join(dir, name), text, { mode: 0o600, flag: 'wx' });
        return true;
      } catch (error) {
        if (error?.code === 'EEXIST') return false;
        throw error;
      }
    },
  };
}

/**
 * A bucket, under `prefix`: each name an object. `secret(key)` reads an
 * object outside the prefix (the leaderboard's key), which only the
 * functions' role may read. The AWS SDK is the Lambda runtime's own.
 */
export async function s3Store(bucket, prefix) {
  const { S3Client, GetObjectCommand, PutObjectCommand } = await import('@aws-sdk/client-s3');
  const s3 = new S3Client({});
  const get = async (key) => {
    try {
      const answer = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
      return await answer.Body.transformToString();
    } catch (error) {
      if (error?.name === 'NoSuchKey' || error?.$metadata?.httpStatusCode === 404) return null;
      throw error;
    }
  };
  const put = (name, text, extra = {}) =>
    s3.send(new PutObjectCommand({ Bucket: bucket, Key: prefix + name, Body: text, ContentType: 'application/json', ServerSideEncryption: 'AES256', ...extra }));
  return {
    shared: true,
    read: (name) => get(prefix + name),
    write: async (name, text) => {
      await put(name, text);
    },
    async create(name, text) {
      try {
        await put(name, text, { IfNoneMatch: '*' });
        return true;
      } catch (error) {
        if (error?.$metadata?.httpStatusCode === 412 || error?.name === 'PreconditionFailed') return false;
        throw error;
      }
    },
    secret: get,
  };
}
