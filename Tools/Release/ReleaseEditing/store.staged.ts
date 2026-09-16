import { mutateMetadata, readReleasesJson } from "@/lib/storage";

/**
 * Where releases live.
 *
 * One JSON document rather than a database. Releases are written on this site
 * now, so the site has to own them — and for a handful of posts a single
 * document is the whole system: no schema, no migrations, no connection string.
 *
 * Reading and writing that document is `storage.ts`'s problem, not this file's.
 * Everything here is list manipulation, which is why swapping a disk for object
 * storage did not touch a line of it.
 */
export interface StoredRelease {
  tag: string;
  name: string;
  date: string;
  /** Markdown. */
  body: string;
  images: { src: string; alt: string }[];
  videos: string[];
  /** GitHub usernames, credited with a link. */
  contributors: string[];
  prerelease: boolean;
  /** Hidden from the public list until published. */
  draft: boolean;
  /** Testers only. A draft is unfinished; this is finished but not for everyone. */
  private?: boolean;
  /** The build itself, where there is one. */
  download?: { url: string; name: string; size: number };
}

/** Thrown when an edit's source is gone or a rename target is taken. */
export class ReleaseConflictError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReleaseConflictError";
  }
}

export async function readAll(strict = false): Promise<StoredRelease[]> {
  try {
    const raw = await readReleasesJson();
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error("Invalid metadata list");
    return parsed as StoredRelease[];
  } catch (error) {
    if (strict) throw error;
    // Missing or unreadable is an empty list, not a broken page. A storage
    // outage should cost you the releases section, not the whole site.
    return [];
  }
}

function encodeReleases(list: StoredRelease[]) {
  return `${JSON.stringify(list, null, 2)}\n`;
}

function parseReleasesList(raw: string | null): StoredRelease[] {
  if (!raw) return [];
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed)) throw new Error("Invalid metadata list");
  return parsed as StoredRelease[];
}

function sortReleases(list: StoredRelease[]) {
  list.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
}

/**
 * Create or replace by tag — the tag is the identity.
 *
 * When `previousTag` is supplied the rename is one conditional write: the
 * source tag must still exist, and a changed tag must not belong to another
 * record. A failed rename leaves the stored list untouched. Without it the
 * historical create-or-replace semantics apply.
 *
 * Both paths run inside a single `mutateMetadata` callback — no preliminary
 * read — so concurrent editors cannot interleave a read and a write. Supplied
 * by Walter's `storage.ts` primitive; this file only does list manipulation.
 */
export async function upsert(release: StoredRelease, previousTag?: string) {
  return mutateMetadata<StoredRelease>("releases.json", (raw) => {
    const list = parseReleasesList(raw);
    if (previousTag !== undefined) {
      const srcIdx = list.findIndex((r) => r.tag === previousTag);
      if (srcIdx < 0) {
        throw new ReleaseConflictError(`Original release "${previousTag}" no longer exists`);
      }
      if (release.tag !== previousTag && list.some((r, i) => i !== srcIdx && r.tag === release.tag)) {
        throw new ReleaseConflictError(`Release "${release.tag}" already exists`);
      }
      const next = list.filter((_, i) => i !== srcIdx);
      next.unshift(release);
      sortReleases(next);
      return { text: encodeReleases(next), result: release };
    }
    const next = list.slice();
    const i = next.findIndex((r) => r.tag === release.tag);
    if (i >= 0) next[i] = release;
    else next.unshift(release);
    sortReleases(next);
    return { text: encodeReleases(next), result: release };
  });
}

export async function remove(tag: string) {
  return mutateMetadata<void>("releases.json", (raw) => {
    const next = parseReleasesList(raw).filter((r) => r.tag !== tag);
    return { text: encodeReleases(next), result: undefined };
  });
}
