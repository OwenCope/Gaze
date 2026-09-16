import type { Settings } from "./settings";
import type { Tester } from "./testers";
import { PERMISSIONS, type Role } from "./permissions";

const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const strings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === "string");

export function isSettings(value: unknown): value is Settings {
  return record(value) && typeof value.releasesRequireSignIn === "boolean";
}

export function isTesterList(value: unknown): value is Tester[] {
  return Array.isArray(value) && value.every((item) => record(item) &&
    typeof item.email === "string" && item.email.length > 0 &&
    typeof item.addedAt === "string" &&
    (item.roles === undefined || strings(item.roles)) &&
    (item.github === undefined || typeof item.github === "string") &&
    (item.note === undefined || typeof item.note === "string"));
}

export function isRoleList(value: unknown): value is Role[] {
  return Array.isArray(value) && value.every((item) => record(item) &&
    typeof item.id === "string" && item.id.length > 0 &&
    typeof item.name === "string" && typeof item.color === "string" &&
    strings(item.permissions) && item.permissions.every((p) => Object.hasOwn(PERMISSIONS, p)));
}

export async function readAdminResponse<T>(
  response: Response,
  valid: (value: unknown) => value is T,
  failure: string,
): Promise<T> {
  let value: unknown;
  try { value = await response.json(); } catch { value = null; }
  if (!response.ok) {
    const message = record(value) && typeof value.error === "string" && value.error.trim()
      ? value.error : `${failure} (HTTP ${response.status})`;
    throw new Error(message);
  }
  if (!valid(value)) throw new Error("The change could not be confirmed. Reload before trying again.");
  return value;
}
