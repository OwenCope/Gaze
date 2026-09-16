import { mutateMetadata, readTestersJson } from "@/lib/storage";

/**
 * Who is allowed to see a private release.
 *
 * Kept as its own document rather than a field on each release, so the list
 * survives every release rather than being retyped for each one — and so
 * removing someone removes them from everything at once, which is what you
 * want the moment you need to remove someone.
 */
export interface Tester {
  /** Lowercased. This is the identity — it is what Google gives back at sign-in. */
  email: string;
  /** Role ids. Everyone added gets 'tester' unless told otherwise. */
  roles?: string[];
  /** Optional, for the link on the list. */
  github?: string;
  /** Whatever you want to remember about them. */
  note?: string;
  addedAt: string;
}

export async function readTesters(strict = false): Promise<Tester[]> {
  try {
    const raw = await readTestersJson();
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error("Invalid metadata list");
    return parsed as Tester[];
  } catch (error) {
    if (strict) throw error;
    return [];
  }
}

const clean = (email: string) => email.trim().toLowerCase();

export async function addTester(input: {
  email: string;
  github?: string;
  note?: string;
  roles?: string[];
}): Promise<Tester[]> {
  // Computed once: the retryable callback below may run up to five times on a
  // Blob precondition conflict, and every attempt must use the same values.
  const email = clean(input.email);
  const github = input.github?.trim().replace(/^@/, "").replace(/^https?:\/\/github\.com\//, "");
  const note = input.note?.trim() || undefined;
  const explicitRoles = input.roles ? [...input.roles] : undefined;
  const nowIso = new Date().toISOString();

  return mutateMetadata<Tester[]>('testers.json', (raw) => {
    const list: Tester[] = raw ? (JSON.parse(raw) as Tester[]) : [];
    if (!Array.isArray(list)) throw new Error("Invalid metadata list");
    const existing = list.findIndex((t) => t.email === email);
    const record: Tester = {
      email,
      roles: explicitRoles ?? list[existing]?.roles ?? ["tester"],
      github: github || undefined,
      note,
      // Adding someone twice updates them rather than duplicating the row, and
      // keeps the date they were first let in.
      addedAt: existing >= 0 ? list[existing].addedAt : nowIso,
    };

    if (existing >= 0) list[existing] = record;
    else list.unshift(record);

    return { text: `${JSON.stringify(list, null, 2)}\n`, result: list };
  });
}

export async function removeTester(email: string): Promise<Tester[]> {
  const target = clean(email);
  return mutateMetadata<Tester[]>('testers.json', (raw) => {
    const list: Tester[] = raw ? (JSON.parse(raw) as Tester[]) : [];
    if (!Array.isArray(list)) throw new Error("Invalid metadata list");
    const next = list.filter((t) => t.email !== target);
    return { text: `${JSON.stringify(next, null, 2)}\n`, result: next };
  });
}

/**
 * Whether this signed-in address may see private releases.
 *
 * Admins always can. Comparison is on the lowercased address, because Google
 * returns whatever case the person typed when they made the account.
 */
export async function isTester(email: string | null | undefined): Promise<boolean> {
  if (!email) return false;
  const list = await readTesters();
  return list.some((t) => t.email === clean(email));
}
