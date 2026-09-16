"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import { useRouter } from "next/navigation";
import { LiquidButton } from "@/components/ui/liquid-glass-button";

/**
 * The tester page's notes, in markdown.
 *
 * One textarea and a save. There is no preview: the notes render on /testers
 * with the same stylesheet as a release, so the preview would be a second
 * rendering to keep honest and the real thing is one click away.
 *
 * Save feedback is truthful: only the exact text the server accepted counts
 * as saved. The draft stays editable while a request is in flight and a late
 * response never overwrites newer typing.
 */
export function ReadmeEditor({ initial }: { initial: string }) {
  const router = useRouter();
  const [text, setText] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [savedText, setSavedText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Synchronous guard: React state updates are async, so rapid clicks or a
  // click plus keyboard shortcut could otherwise send duplicate requests
  // before `busy` flips. The ref flips in the same tick as the check.
  const inFlightRef = useRef(false);

  // Saved only when the live draft still equals the text the server accepted.
  const saved = savedText !== null && text === savedText;

  const save = async () => {
    if (inFlightRef.current) return;
    inFlightRef.current = true;
    setBusy(true);
    setError(null);
    // Capture the draft at submit time. Edits typed while the request is
    // pending stay in `text`; only this snapshot is sent and marked saved.
    const submitted = text;
    try {
      const res = await fetch("/api/readme", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ readme: submitted }),
      });
      let data: { error?: unknown; ok?: unknown } | null = null;
      try {
        data = (await res.json()) as { error?: unknown; ok?: unknown };
      } catch {
        data = null;
      }
      if (!res.ok) {
        const message =
          data !== null &&
          typeof data.error === "string" &&
          data.error.length > 0
            ? data.error
            : "Could not save";
        throw new Error(message);
      }
      if (data?.ok !== true) throw new Error("Save could not be confirmed. Refresh before retrying.");
      // Record exactly what was accepted. `text` is untouched here so a
      // newer draft is never replaced by a late response, and `router`
      // refresh keeps client state (`initial` is only the mount value).
      setSavedText(submitted);
      router.refresh();
    } catch (e) {
      const message = e instanceof Error && e.message ? e.message : "Could not save";
      setError(message);
    } finally {
      inFlightRef.current = false;
      setBusy(false);
    }
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.metaKey !== e.ctrlKey && !e.altKey && !e.shiftKey) {
      if (e.key === "Enter" || e.key.toLowerCase() === "s") {
        e.preventDefault();
        void save();
      }
    }
  };

  return (
    <div className="rounded-[20px] panel p-7">
      <label
        htmlFor="tester-notes"
        className="mb-2 block text-[14px] font-medium text-[var(--muted-ink)]"
      >
        Tester notes
      </label>
      <textarea
        id="tester-notes"
        rows={20}
        value={text}
        onChange={(e) => {
          setText(e.target.value);
        }}
        onKeyDown={onKeyDown}
        aria-busy={busy}
        placeholder={"## Installing\n\nOpen the disk image and drag Gaze to Applications.\n\n## Known issues\n\n- The panel is a few points off on 14-inch models.\n"}
        className="w-full resize-y rounded-[12px] border border-[var(--surface-edge)] bg-[var(--background)] px-3.5 py-3 font-[inherit] text-[16px] leading-relaxed text-[var(--foreground)] outline-none transition-colors placeholder:text-[var(--faint-ink)] focus:border-[var(--faint-ink)]/50"
      />

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <LiquidButton
          variant="solid"
          size="default"
          disabled={busy}
          title="Save (Cmd+S or Ctrl+S)"
          onClick={() => void save()}
        >
          {busy ? "Saving…" : "Save notes"}
        </LiquidButton>
        {saved && (
          <span role="status" className="text-[14px] text-[var(--system-green)]">
            Saved
          </span>
        )}
        {error && (
          <span role="alert" className="text-[14px] text-[#FF9500]">
            {error}
          </span>
        )}
      </div>
    </div>
  );
}
