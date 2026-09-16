import { mutateMetadata, readRolesJson } from "@/lib/storage";
import { PERMISSIONS, type Permission, type Role } from "@/lib/permissions";

export { PERMISSIONS };
export type { Permission, Role };

/**
 * The role everyone starts with, seeded on first read.
 *
 * Owner is not in here and cannot be. It comes from ADMIN_EMAILS in the
 * environment, so no amount of editing this list can promote anyone — a role
 * system whose top role is editable by the role system is a lock with the key
 * taped to it.
 */
const DEFAULT_ROLES: Role[] = [
  {
    id: "tester",
    name: "Tester",
    color: "#34C759",
    permissions: ["viewPrivate"],
  },
];

export async function readRoles(strict = false): Promise<Role[]> {
  try {
    const raw = await readRolesJson();
    if (!raw) return DEFAULT_ROLES;
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error("Invalid role metadata");
    return parsed as Role[];
  } catch (error) {
    if (strict) throw error;
    return [];
  }
}

function copyDefaultRoles(): Role[] {
  // Never hand out (or mutate) the shared DEFAULT_ROLES array: every mutation
  // starts from a fresh copy so a failed write cannot leave defaults changed.
  return DEFAULT_ROLES.map((r) => ({ ...r, permissions: [...r.permissions] }));
}

async function mutateRoles(update: (list: Role[]) => Role[]): Promise<Role[]> {
  return mutateMetadata<Role[]>('roles.json', (raw) => {
    const list: Role[] = raw ? (JSON.parse(raw) as Role[]) : copyDefaultRoles();
    if (!Array.isArray(list)) throw new Error("Invalid role metadata");
    const next = update(list);
    return { text: `${JSON.stringify(next, null, 2)}\n`, result: next };
  });
}

const slug = (name: string) =>
  name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "role";

export async function upsertRole(input: {
  id?: string;
  name: string;
  color: string;
  permissions: Permission[];
}): Promise<Role[]> {
  // Computed once: retries must reuse the same identity and values.
  const id = input.id || slug(input.name);
  const role: Role = {
    id,
    name: input.name.trim() || "Role",
    color: input.color,
    permissions: input.permissions.filter((p) => p in PERMISSIONS),
  };
  return mutateRoles((list) => {
    const i = list.findIndex((r) => r.id === id);
    if (i >= 0) list[i] = { ...role, permissions: [...role.permissions] };
    else list.push({ ...role, permissions: [...role.permissions] });
    return list;
  });
}

export async function removeRole(id: string): Promise<Role[]> {
  const target = id;
  return mutateRoles((list) => list.filter((r) => r.id !== target));
}
