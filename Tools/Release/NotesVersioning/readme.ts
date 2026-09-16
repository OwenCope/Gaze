import { createHash } from "node:crypto";
import { mutateMetadata, readReadme } from "./storage";

/**
 * Versioned tester notes.
 *
 * Two admins editing the same markdown document cannot merge by row the way
 * two tester additions can: the whole text is one value. The guard here is
 * therefore optimistic concurrency, not recomputation. Every read carries a
 * content version and every write must present the version it was based on;
 * a stale presenter loses with a `ReadmeConflictError` and its draft is
 * never written.
 *
 * Versions are SHA-256 hex of the UTF-8 text, except that an absent local
 * document versions as the literal `"missing"`. An existing empty document
 * (`""`, whose hash is `e3b0c44…`) and a missing local document are
 * therefore distinct versions with the same edited text (`""`).
 *
 * Blob mode never infers a missing private object as empty: `mutateMetadata`
 * refuses a missing, non-200, ETag-less, or corrupt read before the update
 * callback runs, so an unmigrated store stays refused and the callback below
 * only ever compares against a version that was actually read.
 */
export class ReadmeConflictError extends Error {
  constructor(message?: string) {
    super(
      message ??
        "Someone else saved newer notes. Your draft was kept. " +
          "Reload the saved notes to see their version, then re-apply your changes.",
    );
    this.name = "ReadmeConflictError";
  }
}

/** Content version for a raw document: `"missing"` for absent local data, else SHA-256 hex. */
export function versionForReadme(raw: string | null): string {
  if (raw === null) return "missing";
  return createHash("sha256").update(raw, "utf8").digest("hex");
}

export async function readReadmeDocument(): Promise<{ text: string; version: string }> {
  const raw = await readReadme();
  return { text: raw ?? "", version: versionForReadme(raw) };
}

/**
 * Save `text` only if the stored document still versions as
 * `expectedVersion`. The comparison runs first inside the mutation callback,
 * before any next state is created; a mismatch throws `ReadmeConflictError`
 * without writing. Success stores the submitted text and returns it with its
 * new version.
 */
export async function saveReadmeDocument(
  text: string,
  expectedVersion: string,
): Promise<{ text: string; version: string }> {
  return mutateMetadata<{ text: string; version: string }>("readme.md", (raw) => {
    const currentVersion = versionForReadme(raw);
    if (currentVersion !== expectedVersion) {
      throw new ReadmeConflictError();
    }
    return { text, result: { text, version: versionForReadme(text) } };
  });
}
