"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Modal } from "@/components/ui/modal";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { ColorPicker } from "@/components/ui/color-picker";
import { PERMISSIONS, type Permission, type Role } from "@/lib/permissions";
import { isRoleList, readAdminResponse } from "@/lib/admin-response";

const tint = (hex: string, pct: number) =>
  `color-mix(in srgb, ${hex} ${pct}%, transparent)`;

/**
 * Roles as chips, with a plus at the end.
 *
 * A chip is the thing itself rather than a row describing it — you see the
 * colour and the name the way they appear everywhere else on the site, and the
 * editor opens over the top instead of sitting permanently beside a list you
 * are not editing.
 *
 * Owner is a chip too, and is not clickable. It comes from the environment, so
 * showing it makes the hierarchy legible without implying it can be changed.
 */
export function RolesManager({ initial }: { initial: Role[] }) {
  const router = useRouter();
  const [roles, setRoles] = useState(initial);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<Role | null>(null);
  const [name, setName] = useState("");
  const [color, setColor] = useState("#34C759");
  const [perms, setPerms] = useState<Permission[]>([]);
  const [pending, setPending] = useState<"save" | "remove" | null>(null);
  const busy = pending !== null;
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);

  const openNew = () => {
    if (inFlight.current) return;
    setError(null);
    setEditing(null);
    setName("");
    setColor("#34C759");
    setPerms([]);
    setOpen(true);
  };

  const openEdit = (r: Role) => {
    if (inFlight.current) return;
    setError(null);
    setEditing(r);
    setName(r.name);
    setColor(r.color);
    setPerms(r.permissions);
    setOpen(true);
  };

  const save = async () => {
    if (inFlight.current || !name.trim()) return;
    inFlight.current = true;
    setPending("save");
    setError(null);
    const submitted = { id: editing?.id, name: name.trim(), color, permissions: [...perms] };
    try {
      const res = await fetch("/api/roles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(submitted),
      });
      const list = await readAdminResponse(res, isRoleList, "Could not save role");
      const confirmed = list.find((role) =>
        (submitted.id ? role.id === submitted.id : role.name === submitted.name) &&
        role.name === submitted.name && role.color.toLowerCase() === submitted.color.toLowerCase() &&
        JSON.stringify([...role.permissions].sort()) === JSON.stringify([...submitted.permissions].sort()));
      if (!confirmed) throw new Error("The change could not be confirmed. Reload before trying again.");
      setRoles(list);
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save role");
    } finally {
      inFlight.current = false;
      setPending(null);
    }
  };

  const remove = async () => {
    if (inFlight.current || !editing || !window.confirm(`Delete ${editing.name}? People with this role will lose its permissions.`)) return;
    inFlight.current = true;
    setPending("remove");
    setError(null);
    const id = editing.id;
    try {
      const res = await fetch(`/api/roles?id=${encodeURIComponent(id)}`, { method: "DELETE" });
      const list = await readAdminResponse(res, isRoleList, "Could not delete role");
      if (list.some((role) => role.id === id)) throw new Error("The deletion could not be confirmed. Reload before trying again.");
      setRoles(list);
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not delete role");
    } finally {
      inFlight.current = false;
      setPending(null);
    }
  };

  const toggle = (p: Permission) =>
    setPerms((l) => (l.includes(p) ? l.filter((x) => x !== p) : [...l, p]));

  return (
    <>
      <div className="flex flex-wrap items-center gap-2.5">
        <span
          className="inline-flex h-9 cursor-default items-center gap-2 rounded-full px-3.5 text-[14px] font-medium"
          style={{ backgroundColor: tint("var(--foreground)", 8) }}
          title="Comes from the environment, not from here"
        >
          <span className="size-2 rounded-full bg-[var(--foreground)]" />
          Owner
        </span>

        {roles.map((r) => (
          <button
            key={r.id}
            type="button"
            disabled={busy}
            onClick={() => openEdit(r)}
            className="inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-full px-3.5 text-[14px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
            style={{ color: r.color, backgroundColor: tint(r.color, 16) }}
          >
            <span className="size-2 rounded-full" style={{ backgroundColor: r.color }} />
            {r.name}
          </button>
        ))}

        <button
          type="button"
          disabled={busy}
          onClick={openNew}
          aria-label="New role"
          className="flex size-11 cursor-pointer items-center justify-center rounded-full border border-dashed border-[var(--faint-ink)]/50 text-[var(--faint-ink)] transition-colors hover:border-[var(--foreground)] hover:text-[var(--foreground)]"
        >
          <svg viewBox="0 0 24 24" className="size-4" fill="none" aria-hidden>
            <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      {!open && busy && <p role="status" className="mt-3 text-[14px] text-[var(--muted-ink)]">Saving changes…</p>}
      {!open && error && <p role="alert" className="mt-3 text-[14px] text-[var(--destructive)]">{error}</p>}
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? "Edit role" : "New role"}>
        <div className="h-16" style={{ backgroundColor: tint(color, 28) }} />

        <form className="max-h-[calc(100dvh-8rem)] overflow-y-auto p-6" aria-busy={busy} onSubmit={(event) => { event.preventDefault(); void save(); }}>
          <fieldset disabled={busy} className="min-w-0">
          <label htmlFor="role-name" className="mb-2 block text-[14px] font-medium">Role name</label>
          <input
            id="role-name"
            name="name"
            required
            autoFocus={typeof window !== "undefined" && window.matchMedia("(pointer: fine)").matches}
            autoComplete="off"
            spellCheck={false}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Role name"
            className="w-full bg-transparent text-[22px] font-semibold tracking-[-0.02em] outline-none placeholder:text-[var(--faint-ink)] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--foreground)]"
          />

          <div className="mt-5">
            <ColorPicker value={color} onChange={(value) => { if (!inFlight.current) setColor(value); }} />
          </div>

          <div className="mt-6 space-y-3 border-t border-[var(--hairline)] pt-5">
            {(Object.keys(PERMISSIONS) as Permission[]).map((p) => (
              <label key={p} className="flex cursor-pointer items-start gap-3 text-[15px]">
                <input
                  type="checkbox"
                  checked={perms.includes(p)}
                  onChange={() => toggle(p)}
                  className="mt-0.5 size-4 accent-[var(--system-green)]"
                />
                <span className="leading-snug text-[var(--muted-ink)]">{PERMISSIONS[p]}</span>
              </label>
            ))}
          </div>

          {error && <p role="alert" className="mt-4 text-[14px] text-[var(--destructive)]">{error}</p>}
          <div className="mt-7 flex items-center gap-2.5">
            <LiquidButton type="submit" variant="solid" size="default" disabled={busy}>
              {pending === "save" ? "Saving…" : editing ? "Save" : "Create"}
            </LiquidButton>
            {editing && (
              <button
                type="button"
                disabled={busy}
                onClick={() => void remove()}
                className="ml-auto cursor-pointer rounded-full px-3 py-2 text-[14px] text-[var(--faint-ink)] transition-colors hover:text-[#FF375F]"
              >
                {pending === "remove" ? "Deleting…" : "Delete role"}
              </button>
            )}
          </div>
          </fieldset>
        </form>
      </Modal>
    </>
  );
}
