import { BlobPreconditionFailedError, get, put } from "@vercel/blob";
import { randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

/**
 * Where the site keeps what it writes.
 *
 * Vercel's filesystem is read-only at runtime, so a release published on the
 * site cannot be saved to a file next to the code — it goes to Vercel Blob,
 * which is object storage the running site is allowed to write to.
 *
 * Two backends, chosen by whether a Blob token is present. That is not
 * indecision: without the fallback, `npm run dev` on a laptop with no token
 * would fail to render the releases page at all, and the first thing anyone
 * does with this repo is run it locally.
 */
const KEY = "releases.json";
const TESTERS_KEY = "testers.json";
const README_KEY = "readme.md";
const ROLES_KEY = "roles.json";
const DISK = path.join(process.cwd(), "data", KEY);
const TESTERS_DISK = path.join(process.cwd(), "data", TESTERS_KEY);
const README_DISK = path.join(process.cwd(), "data", README_KEY);
const ROLES_DISK = path.join(process.cwd(), "data", ROLES_KEY);

/**
 * OIDC (`BLOB_STORE_ID`) is what Vercel wires up by default; the static token
 * is the fallback and is what `vercel env pull` puts in `.env.local`.
 *
 * Public credentials continue to belong to the upload route. Any Blob
 * configuration, or a Vercel deployment, requires private metadata configuration;
 * local disk is used only outside Vercel with no Blob configuration at all.
 */
export const usingBlob = Boolean(
  process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_STORE_ID
    || process.env.BLOB_PRIVATE_READ_WRITE_TOKEN || process.env.BLOB_PRIVATE_STORE_ID
    || process.env.VERCEL === "1",
);

/**
 * Private metadata storage.
 *
 * `releases.json` carries drafts and tester-only releases, `testers.json`
 * carries tester emails, `roles.json` carries the permission map, and
 * `settings.json` carries the visibility switch. Route-level gates decide who
 * may *ask*, but every one of these documents used to sit at a public Blob
 * URL on the same store whose hostname is printed in public build links — so
 * anyone who could guess the pathname could read them without asking at all.
 *
 * Metadata therefore lives in a dedicated store, addressed only by pathname
 * through the server SDK with `access: "private"`. The credential is explicit
 * and separate: `BLOB_PRIVATE_READ_WRITE_TOKEN` (static token) and/or
 * `BLOB_PRIVATE_STORE_ID` (OIDC), taken from that store — never the public
 * store's values. Reads keep `useCache: false`, for the same reason as before:
 * someone added a minute ago must be visible a minute later.
 *
 * Fail-closed: when the site runs on Blob (see `usingBlob`) but the private
 * store is not configured, every metadata helper throws instead of quietly
 * reading from or writing to the public store. The local-disk fallback in each
 * helper below is only for development and tests with no Blob configuration
 * at all — it is not a production path.
 */
export const usingPrivateMetadataStore = Boolean(
  process.env.BLOB_PRIVATE_READ_WRITE_TOKEN || process.env.BLOB_PRIVATE_STORE_ID,
);

const PRIVATE_STORE_UNCONFIGURED =
  "Private metadata store is not configured: set BLOB_PRIVATE_READ_WRITE_TOKEN " +
  "and/or BLOB_PRIVATE_STORE_ID from the dedicated private Blob store. Refusing " +
  "to fall back to the public store.";

function privateStoreOptions(): { access: "private"; token?: string; storeId?: string; oidcToken?: string } {
  const token = process.env.BLOB_PRIVATE_READ_WRITE_TOKEN?.trim();
  const storeId = process.env.BLOB_PRIVATE_STORE_ID?.trim();
  if (!token && !storeId) throw new Error(PRIVATE_STORE_UNCONFIGURED);
  if (token && token === process.env.BLOB_READ_WRITE_TOKEN?.trim()) {
    throw new Error("Metadata must use a separate private Blob credential.");
  }
  if (storeId && storeId.replace(/^store_/, "") === process.env.BLOB_STORE_ID?.replace(/^store_/, "")) {
    throw new Error("Metadata must use a separate private Blob store.");
  }
  if (token) return { access: "private", token };
  const oidcToken = process.env.VERCEL_OIDC_TOKEN?.trim();
  // An explicit OIDC token prevents the SDK falling back to the public token.
  if (!oidcToken) throw new Error("Private Blob OIDC requires VERCEL_OIDC_TOKEN; configure a private read-write token otherwise.");
  return { access: "private", storeId, oidcToken };
}

function validateMetadata(key: string, text: string): void {
  if (key === README_KEY) return;
  const value: unknown = JSON.parse(text);
  if ([KEY, TESTERS_KEY, ROLES_KEY].includes(key)) {
    if (!Array.isArray(value)) throw new Error(`Invalid metadata list: ${key}`);
  } else if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Invalid metadata object: ${key}`);
  }
}

async function readPrivateMetadata(key: string): Promise<string> {
  const response = await get(key, { ...privateStoreOptions(), useCache: false });
  if (!response || response.statusCode !== 200) {
    throw new Error(`Private metadata unavailable: ${key}. Complete and verify migration before using this store.`);
  }
  const text = await new Response(response.stream).text();
  validateMetadata(key, text);
  return text;
}

async function writePrivateMetadata(key: string, value: string, contentType: string): Promise<void> {
  validateMetadata(key, value);
  // Do not seed an empty or incomplete migration through an ordinary admin write.
  await readPrivateMetadata(key);
  await put(key, value, { ...privateStoreOptions(), contentType,
    addRandomSuffix: false, allowOverwrite: true, cacheControlMaxAge: 60 });
}

/**
 * Compare-and-swap mutation for the JSON metadata documents.
 *
 * Two admins adding different testers at the same time used to race: both
 * read the same list, each appended their own row, and the second write
 * silently discarded the first. This helper closes that loss for
 * independent-record updates by retrying the read/modify/write cycle against
 * the version that is current at write time.
 *
 * Blob mode (production): each attempt reads the private object with
 * `useCache: false` and the existing explicit private credentials, requires a
 * 200 response with valid existing content and a nonempty ETag, runs the pure
 * `update` callback, validates the next text, and writes with
 * `access: "private"`, `addRandomSuffix: false`, `allowOverwrite: true` and
 * `ifMatch` set to the ETag just read. A `BlobPreconditionFailedError` from
 * the installed SDK (checked with `instanceof`, since SDK errors inherit
 * `Error` with name `"Error"`) means another writer won the race, so the
 * cycle re-reads and recomputes, up to five attempts total. Only the result
 * belonging to the successful conditional write is returned. A missing,
 * non-200, ETag-less, corrupt, or unconfigured read never calls `update` and
 * never writes, so an ordinary mutation cannot initialize an unmigrated
 * store. Exhaustion throws an actionable error that names the key and the
 * retry count without including private document content.
 *
 * Local mode (no Blob configuration): mutations for the same key are
 * serialized within this process by a per-key promise queue that survives a
 * failed predecessor, so two concurrent `mutateMetadata` calls cannot
 * interleave their read/modify/write cycles. A missing file reads as `null`
 * only on `ENOENT`; any other filesystem error propagates without writing.
 * Existing and next content are both validated. Each mutation writes a unique
 * temporary file in the same directory and renames it atomically over the
 * target, always cleaning up the owned temp file. This queue does NOT
 * coordinate independent local processes (two dev servers, scripts, etc.):
 * writers in different processes can still race. No lock files are used, so
 * there is nothing stale to delete. Blob mode is the concurrent-safe path.
 *
 * The production/local backend selection (`usingBlob`) and the private
 * credential safeguards (`privateStoreOptions`) are unchanged.
 */
export type MetadataMutationKey =
  | 'releases.json'
  | 'testers.json'
  | 'roles.json'
  | 'settings.json';

const MUTATE_MAX_ATTEMPTS = 5;

const mutationGlobals = globalThis as typeof globalThis & {
  __gazeMetadataQueues?: Map<string, Promise<void>>;
};
const localMutationQueues = mutationGlobals.__gazeMetadataQueues ??= new Map<string, Promise<void>>();
const MUTATION_KEYS = new Set([KEY, TESTERS_KEY, ROLES_KEY, "settings.json"]);

function diskPathForMetadataKey(key: string): string {
  return path.join(process.cwd(), "data", key);
}

export async function mutateMetadata<T>(
  key: 'releases.json' | 'testers.json' | 'roles.json' | 'settings.json',
  update: (raw: string | null) => { text: string; result: T },
): Promise<T> {
  if (!MUTATION_KEYS.has(key)) throw new Error("Unsupported metadata document");
  if (!usingBlob) {
    const queueKey = diskPathForMetadataKey(key);
    const previous = localMutationQueues.get(queueKey) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(async (): Promise<T> => {
      let raw: string | null;
      try {
        raw = await fs.readFile(diskPathForMetadataKey(key), "utf8");
      } catch (error) {
        if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") raw = null;
        else throw error;
      }
      if (raw !== null) validateMetadata(key, raw);
      const next = update(raw);
      validateMetadata(key, next.text);
      const disk = diskPathForMetadataKey(key);
      await fs.mkdir(path.dirname(disk), { recursive: true });
      const tmp = `${disk}.${randomUUID()}.tmp`;
      let created = false;
      try {
        const file = await fs.open(tmp, "wx", 0o600);
        created = true;
        try { await file.writeFile(next.text, "utf8"); } finally { await file.close(); }
        await fs.rename(tmp, disk);
      } finally {
        if (created) await fs.unlink(tmp).catch((error: NodeJS.ErrnoException) => {
          if (error.code !== "ENOENT") throw error;
        });
      }
      return next.result;
    });
    // The stored tail never rejects so one failure does not wedge the queue;
    // the returned `run` still rejects for its own caller.
    const tail = run.then(() => {}, () => {});
    localMutationQueues.set(queueKey, tail);
    void tail.then(() => {
      if (localMutationQueues.get(queueKey) === tail) localMutationQueues.delete(queueKey);
    });
    return run;
  }

  let attempt = 0;
  while (true) {
    attempt += 1;
    const response = await get(key, { ...privateStoreOptions(), useCache: false });
    if (!response || response.statusCode !== 200) {
      throw new Error(
        `Private metadata unavailable: ${key}. Complete and verify migration before using this store.`,
      );
    }
    const etag = response.blob?.etag;
    if (typeof etag !== "string" || etag.trim().length === 0) {
      throw new Error(
        `Private metadata unavailable: ${key} is missing a version (ETag). Refusing conditional write.`,
      );
    }
    const current = await new Response(response.stream).text();
    validateMetadata(key, current);
    const next = update(current);
    validateMetadata(key, next.text);
    try {
      await put(key, next.text, {
        ...privateStoreOptions(),
        contentType: "application/json",
        addRandomSuffix: false,
        allowOverwrite: true,
        cacheControlMaxAge: 60,
        ifMatch: etag,
      });
      return next.result;
    } catch (error) {
      // SDK errors inherit Error with name "Error": match by class, not by name.
      if (error instanceof BlobPreconditionFailedError) {
        if (attempt >= MUTATE_MAX_ATTEMPTS) {
          throw new Error(
            `Concurrent update conflict on ${key}: another writer updated the document; ` +
            `tried ${MUTATE_MAX_ATTEMPTS} times. Reload and retry.`,
          );
        }
        continue;
      }
      throw error;
    }
  }
}

export async function readReleasesJson(): Promise<string | null> {
  if (!usingBlob) {
    try {
      return await fs.readFile(DISK, "utf8");
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return null;
      throw error;
    }
  }

  // `useCache: false` reads past the CDN. Without it a release could take up to
  // a minute to appear after publishing — you would hit refresh, see the old
  // list, and reasonably conclude it was broken.
  return readPrivateMetadata(KEY);
}

export async function writeReleasesJson(json: string): Promise<void> {
  if (!usingBlob) {
    await fs.mkdir(path.dirname(DISK), { recursive: true });
    await fs.writeFile(DISK, json, "utf8");
    return;
  }

  await writePrivateMetadata(KEY, json, "application/json");
}

/**
 * The tester list. Same two backends, same reasoning — and the same
 * `useCache: false`, because someone added a minute ago must be able to open
 * the release you added them for.
 */
export async function readTestersJson(): Promise<string | null> {
  if (!usingBlob) {
    try {
      return await fs.readFile(TESTERS_DISK, "utf8");
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return null;
      throw error;
    }
  }
  return readPrivateMetadata(TESTERS_KEY);
}

export async function writeTestersJson(json: string): Promise<void> {
  if (!usingBlob) {
    await fs.mkdir(path.dirname(TESTERS_DISK), { recursive: true });
    await fs.writeFile(TESTERS_DISK, json, "utf8");
    return;
  }
  await writePrivateMetadata(TESTERS_KEY, json, "application/json");
}

/** The tester page's notes. Markdown, one document, same two backends. */
export async function readReadme(): Promise<string | null> {
  if (!usingBlob) {
    try {
      return await fs.readFile(README_DISK, "utf8");
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return null;
      throw error;
    }
  }
  return readPrivateMetadata(README_KEY);
}

export async function writeReadme(md: string): Promise<void> {
  if (!usingBlob) {
    await fs.mkdir(path.dirname(README_DISK), { recursive: true });
    await fs.writeFile(README_DISK, md, "utf8");
    return;
  }
  await writePrivateMetadata(README_KEY, md, "text/markdown");
}

/** The role definitions. */
export async function readRolesJson(): Promise<string | null> {
  if (!usingBlob) {
    try {
      return await fs.readFile(ROLES_DISK, "utf8");
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return null;
      throw error;
    }
  }
  return readPrivateMetadata(ROLES_KEY);
}

export async function writeRolesJson(json: string): Promise<void> {
  if (!usingBlob) {
    await fs.mkdir(path.dirname(ROLES_DISK), { recursive: true });
    await fs.writeFile(ROLES_DISK, json, "utf8");
    return;
  }
  await writePrivateMetadata(ROLES_KEY, json, "application/json");
}

/**
 * Settings, read and written by key.
 *
 * Generic rather than another hand-written pair, because the four above are
 * already the same twenty lines four times over and a fifth switch should not
 * cost a fifth copy.
 */
export async function readJSON<T>(key: string): Promise<T | null> {
  if (!usingBlob) {
    try {
      return JSON.parse(await fs.readFile(path.join(process.cwd(), "data", key), "utf8")) as T;
    } catch (error) {
      if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return null;
      throw error;
    }
  }
  return JSON.parse(await readPrivateMetadata(key)) as T;
}

export async function writeJSON(key: string, value: unknown): Promise<void> {
  const json = JSON.stringify(value, null, 2);
  if (!usingBlob) {
    const disk = path.join(process.cwd(), "data", key);
    await fs.mkdir(path.dirname(disk), { recursive: true });
    await fs.writeFile(disk, json, "utf8");
    return;
  }
  await writePrivateMetadata(key, json, "application/json");
}
