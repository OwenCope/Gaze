import { mutateMetadata, readJSON } from "./storage";

/**
 * Site settings the owner can change without a deploy.
 *
 * Deliberately tiny. Anything that belongs in code should stay in code — this
 * is only for switches whose right answer changes with circumstance rather than
 * with the design, and which somebody needs to flip from a phone.
 */
export interface Settings {
  /**
   * Whether the releases page requires signing in at all.
   *
   * Off by default. Private releases are already invisible to people who are
   * not testers; this closes the whole page, for the stretch before a public
   * launch when even knowing which versions exist is more than is wanted.
   */
  releasesRequireSignIn: boolean;
}

const DEFAULTS: Settings = { releasesRequireSignIn: false };

export async function getSettings(): Promise<Settings> {
  const stored = await readJSON<Partial<Settings>>("settings.json");
  // Merged rather than replaced. A settings file written by an older version
  // is missing whatever was added since, and spreading defaults under it means
  // a new switch starts at its default instead of `undefined`.
  return { ...DEFAULTS, ...(stored ?? {}) };
}

export async function saveSettings(next: Partial<Settings>): Promise<Settings> {
  // Captured once so retries merge the same patch against the latest stored
  // document; concurrent patches to different keys both survive.
  const patch: Partial<Settings> = { ...next };
  return mutateMetadata<Settings>('settings.json', (raw) => {
    const stored: Partial<Settings> = raw ? (JSON.parse(raw) as Partial<Settings>) : {};
    const merged: Settings = { ...DEFAULTS, ...(stored ?? {}), ...patch };
    return { text: JSON.stringify(merged, null, 2), result: merged };
  });
}
