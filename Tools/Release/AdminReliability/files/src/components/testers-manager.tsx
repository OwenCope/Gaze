"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Modal } from "@/components/ui/modal";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import type { Tester } from "@/lib/testers";
import type { Role } from "@/lib/permissions";
import { isTesterList, readAdminResponse } from "@/lib/admin-response";

const field =
  "w-full rounded-[12px] border border-[var(--surface-edge)] bg-[var(--background)] px-3.5 py-2.5 text-[16px] text-[var(--foreground)] outline-none transition-colors placeholder:text-[var(--faint-ink)] focus:border-[var(--faint-ink)]/50";

const tint = (hex: string, pct: number) => `color-mix(in srgb, ${hex} ${pct}%, transparent)`;

/**
 * The people who can see private releases.
 *
 * A row is a face and a name; everything else about them lives in the card
 * that opens when you click. Roles, notes, a GitHub link and a remove button
 * on every row turned four people into a database table — and the thing you
 * do most often is look one person up, not scan a grid.
 */
export function TestersManager({ initial, roles }: { initial: Tester[]; roles: Role[] }) {
  const router = useRouter();
  const [people, setPeople] = useState(initial);
  const [viewing, setViewing] = useState<Tester | null>(null);
  const [adding, setAdding] = useState(false);

  const [email, setEmail] = useState("");
  const [github, setGithub] = useState("");
  const [note, setNote] = useState("");
  const [chosen, setChosen] = useState<string[]>(["tester"]);
  const [pending, setPending] = useState<"save" | "remove" | null>(null);
  const busy = pending !== null;
  const inFlight = useRef(false);
  const [error, setError] = useState<string | null>(null);

  const roleOf = (id: string) => roles.find((r) => r.id === id);
  const topRole = (t: Tester) => (t.roles ?? []).map(roleOf).find(Boolean) ?? null;

  const submit = async (payload: {
    email: string;
    github?: string;
    note?: string;
    roles?: string[];
  }): Promise<Tester | null> => {
    if (inFlight.current) return null;
    inFlight.current = true;
    setPending("save");
    setError(null);
    try {
      const res = await fetch("/api/testers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const list = await readAdminResponse(res, isTesterList, "Could not save tester");
      const confirmed = list.find((person) => person.email === payload.email.trim().toLowerCase());
      if (!confirmed || JSON.stringify([...(confirmed.roles ?? [])].sort()) !== JSON.stringify([...(payload.roles ?? [])].sort())) {
        throw new Error("The change could not be confirmed. Reload before trying again.");
      }
      setPeople(list);
      router.refresh();
      return confirmed;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save");
      return null;
    } finally {
      inFlight.current = false;
      setPending(null);
    }
  };

  const add = async () => {
    if (!email.trim()) return;
    if (await submit({ email, github, note, roles: chosen })) {
      setEmail("");
      setGithub("");
      setNote("");
      setChosen(["tester"]);
      setAdding(false);
    }
  };

  const setRolesFor = async (t: Tester, ids: string[]) => {
    if (inFlight.current) return;
    setViewing({ ...t, roles: ids });
    const confirmed = await submit({ email: t.email, github: t.github, note: t.note, roles: ids });
    setViewing((current) => current?.email === t.email ? confirmed ?? t : current);
  };

  const remove = async (addr: string) => {
    if (inFlight.current || !window.confirm(`Remove ${addr} from testers? This removes access granted by the tester list.`)) return;
    inFlight.current = true;
    setPending("remove");
    setError(null);
    try {
      const res = await fetch(`/api/testers?email=${encodeURIComponent(addr)}`, { method: "DELETE" });
      const list = await readAdminResponse(res, isTesterList, "Could not remove tester");
      if (list.some((person) => person.email === addr.trim().toLowerCase())) {
        throw new Error("The removal could not be confirmed. Reload before trying again.");
      }
      setPeople(list);
      setViewing(null);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not remove tester");
    } finally {
      inFlight.current = false;
      setPending(null);
    }
  };

  return (
    <>
      <div className="rounded-[20px] panel p-7" aria-busy={busy}>
        <div className="flex items-center justify-between gap-4">
          <h2 className="text-[17px] font-semibold tracking-[-0.01em]">
            People{" "}
            <span className="ml-1 text-[14px] font-normal tabular-nums text-[var(--faint-ink)]">
              {people.length}
            </span>
          </h2>
          <LiquidButton size="default" disabled={busy} onClick={() => { if (inFlight.current) return; setError(null); setAdding(true); }}>
            Add someone
          </LiquidButton>
        </div>

        {people.length === 0 ? (
          <p className="mt-4 leading-relaxed text-[var(--muted-ink)]">
            Nobody yet. Anyone here sees every release you mark private — the list
            carries across releases, so you add someone once.
          </p>
        ) : (
          <ul className="mt-5 grid gap-1.5 sm:grid-cols-2">
            {people.map((t) => {
              const role = topRole(t);
              return (
                <li key={t.email}>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => { if (inFlight.current) return; setError(null); setViewing(t); }}
                    className="flex w-full cursor-pointer items-center gap-3 rounded-[14px] px-3 py-2.5 text-left transition-colors hover:bg-[var(--foreground)]/[0.05]"
                  >
                    <Avatar t={t} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[15px] font-medium">
                        {t.github ? `@${t.github}` : t.email.split("@")[0]}
                      </span>
                      <span
                        className="text-[13px]"
                        style={{ color: role?.color ?? "var(--faint-ink)" }}
                      >
                        {role?.name ?? "No role"}
                      </span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {!adding && !viewing && busy && <p role="status" className="mt-3 text-[14px] text-[var(--muted-ink)]">Saving changes…</p>}
      {!adding && !viewing && error && <p role="alert" className="mt-3 text-[14px] text-[var(--destructive)]">{error}</p>}

      <Modal open={!!viewing} onClose={() => setViewing(null)} title="Profile">
        {viewing && (
          <>
            <div
              className="h-20"
              style={{ backgroundColor: tint(topRole(viewing)?.color ?? "#8E8E93", 30) }}
            />
            <div className="px-6 pb-6">
              <div className="-mt-10 mb-4">
                <span className="inline-block rounded-full ring-4 ring-[var(--background)]">
                  <Avatar t={viewing} big />
                </span>
              </div>

              <h3 className="text-[21px] font-semibold tracking-[-0.02em]">
                {viewing.github ? `@${viewing.github}` : viewing.email.split("@")[0]}
              </h3>
              <p className="mt-0.5 text-[14px] text-[var(--faint-ink)]">{viewing.email}</p>

              {viewing.note && (
                <p className="mt-4 leading-relaxed text-[var(--muted-ink)]">{viewing.note}</p>
              )}

              <div className="mt-5 border-t border-[var(--hairline)] pt-5">
                <div className="flex items-baseline justify-between gap-3">
                  <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-[var(--faint-ink)]">
                    Roles
                  </p>
                  <span role="status" className="text-[12px] text-[var(--muted-ink)]">
                    {busy ? "Saving…" : error ? "Changes not confirmed" : "Changes save automatically"}
                  </span>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {roles.map((r) => {
                    const on = (viewing.roles ?? []).includes(r.id);
                    return (
                      <button
                        key={r.id}
                        type="button"
                        disabled={busy}
                        aria-pressed={on}
                        onClick={() =>
                          void setRolesFor(
                            viewing,
                            on
                              ? (viewing.roles ?? []).filter((x) => x !== r.id)
                              : [...(viewing.roles ?? []), r.id],
                          )
                        }
                        className="min-h-11 cursor-pointer rounded-full px-3 py-1.5 text-[13px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                        style={{
                          color: on ? r.color : "var(--muted-ink)",
                          backgroundColor: on ? tint(r.color, 16) : tint("var(--foreground)", 6),
                        }}
                      >
                        {r.name}
                      </button>
                    );
                  })}
                </div>
              </div>

              {error && <p role="alert" className="mt-4 text-[14px] text-[var(--destructive)]">{error}</p>}
              <div className="mt-7 flex items-center gap-2.5">
                {viewing.github && (
                  <LiquidButton size="default" asChild>
                    <a
                      href={`https://github.com/${viewing.github}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      GitHub
                    </a>
                  </LiquidButton>
                )}
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void remove(viewing.email)}
                  className="ml-auto cursor-pointer rounded-full px-3 py-2 text-[14px] text-[var(--faint-ink)] transition-colors hover:text-[#FF375F]"
                >
                  {pending === "remove" ? "Removing…" : "Remove"}
                </button>
              </div>
            </div>
          </>
        )}
      </Modal>

      <Modal open={adding} onClose={() => setAdding(false)} title="Add someone">
        <form className="max-h-[calc(100dvh-8rem)] overflow-y-auto p-6" aria-busy={busy} onSubmit={(event) => { event.preventDefault(); void add(); }}>
          <h3 className="text-[19px] font-semibold tracking-[-0.02em]">Add someone</h3>
          <p className="mt-1.5 text-[13px] leading-relaxed text-[var(--faint-ink)]">
            The email address they use to sign in. Nothing is emailed — the next
            private release is simply there when they open the site.
          </p>

          <fieldset disabled={busy} className="mt-5 space-y-3">
            <label htmlFor="tester-email" className="block text-[14px] font-medium">Email</label>
            <input
              id="tester-email"
              name="email"
              type="email"
              autoComplete="email"
              required
              autoFocus={typeof window !== "undefined" && window.matchMedia("(pointer: fine)").matches}
              className={field}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="them@example.com"
            />
            <label htmlFor="tester-github" className="block text-[14px] font-medium">GitHub username (optional)</label>
            <input
              id="tester-github"
              name="github"
              autoComplete="off"
              spellCheck={false}
              className={field}
              value={github}
              onChange={(e) => setGithub(e.target.value)}
              placeholder="GitHub username — optional"
            />
            <label htmlFor="tester-note" className="block text-[14px] font-medium">Note (optional)</label>
            <input
              id="tester-note"
              name="note"
              className={field}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="A note — optional"
            />
          </fieldset>

          <div className="mt-5 flex flex-wrap gap-2" role="group" aria-label="Tester roles">
            {roles.map((r) => {
              const on = chosen.includes(r.id);
              return (
                <button
                  key={r.id}
                  type="button"
                  disabled={busy}
                  aria-pressed={on}
                  onClick={() => setChosen((l) => (on ? l.filter((x) => x !== r.id) : [...l, r.id]))}
                  className="min-h-11 cursor-pointer rounded-full px-3 py-1.5 text-[13px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                  style={{
                    color: on ? r.color : "var(--muted-ink)",
                    backgroundColor: on ? tint(r.color, 16) : tint("var(--foreground)", 6),
                  }}
                >
                  {r.name}
                </button>
              );
            })}
          </div>

          {error && <p role="alert" className="mt-4 text-[14px] text-[var(--destructive)]">{error}</p>}

          <div className="mt-6">
            <LiquidButton type="submit" variant="solid" size="default" disabled={busy}>
              {busy ? "Adding…" : "Add"}
            </LiquidButton>
          </div>
        </form>
      </Modal>
    </>
  );
}

function Avatar({ t, big }: { t: Tester; big?: boolean }) {
  const cls = big ? "size-[72px]" : "size-9";
  if (t.github) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={`https://github.com/${t.github}.png?size=160`}
        alt=""
        className={`${cls} shrink-0 rounded-full object-cover`}
      />
    );
  }
  return (
    <span
      className={`${cls} flex shrink-0 items-center justify-center rounded-full bg-[var(--foreground)]/[0.08] font-semibold uppercase text-[var(--faint-ink)] ${
        big ? "text-[26px]" : "text-[14px]"
      }`}
    >
      {t.email.slice(0, 1)}
    </span>
  );
}
