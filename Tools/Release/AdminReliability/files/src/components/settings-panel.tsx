"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Settings } from "@/lib/settings";
import { isSettings, readAdminResponse } from "@/lib/admin-response";

/**
 * The switches the owner can flip without a deploy.
 *
 * Saved on change rather than behind a Save button. There is one switch, its
 * effect is immediate and reversible, and a form that needs submitting for a
 * single toggle is a step invented for its own sake.
 */
export function SettingsPanel({ initial }: { initial: Settings }) {
  const router = useRouter();
  const [settings, setSettings] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const inFlight = useRef(false);

  const set = async (next: Partial<Settings>) => {
    if (inFlight.current) return;
    inFlight.current = true;
    const previous = settings;
    // Moved first, put back on failure. A switch that waits for the network
    // before it moves feels broken on a slow connection.
    setSettings({ ...settings, ...next });
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      const res = await fetch("/api/settings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(next),
      });
      const confirmed = await readAdminResponse(res, isSettings, "Could not save settings");
      if (confirmed.releasesRequireSignIn !== next.releasesRequireSignIn) {
        throw new Error("The change could not be confirmed. Reload before trying again.");
      }
      setSettings(confirmed);
      setSaved(true);
      router.refresh();
    } catch (e) {
      setSettings(previous);
      setError(e instanceof Error ? e.message : "Could not save");
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  };

  return (
    <div className="rounded-[20px] panel p-7" aria-busy={busy}>
      <h2 className="text-[17px] font-semibold tracking-[-0.01em]">Who can see releases</h2>

      <label className="mt-5 flex cursor-pointer items-start gap-3.5">
        <input
          type="checkbox"
          checked={settings.releasesRequireSignIn}
          disabled={busy}
          onChange={(e) => void set({ releasesRequireSignIn: e.target.checked })}
          className="mt-0.5 size-[18px] shrink-0 cursor-pointer accent-[var(--foreground)]"
        />
        <span>
          <span className="block text-[15px] font-medium">Require signing in</span>
          <span className="mt-1 block text-[14px] leading-relaxed text-[var(--muted-ink)]">
            Closes the whole releases page to anyone signed out. Private releases
            are already hidden from people who are not testers — this hides the
            fact that any of them exist.
          </span>
        </span>
      </label>

      {(busy || saved) && <p role="status" className="mt-4 text-[14px] text-[var(--muted-ink)]">{busy ? "Saving…" : "Saved"}</p>}
      {error && <p role="alert" className="mt-4 text-[14px] text-[var(--destructive)]">{error}</p>}
    </div>
  );
}
