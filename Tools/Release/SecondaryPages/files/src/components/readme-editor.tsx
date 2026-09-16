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
 *
 * Stale-edit guard: every save carries the last acknowledged server version
 * (`expectedVersion`). A 409 means another admin saved first; the draft is
 * preserved, the conflict is announced, and the only recovery offered is an
 * explicit reload — never a silent merge, automatic reload, or overwrite.
 */
export function ReadmeEditor({
  initial,
  initialVersion,
}: {
  initial: string;
  initialVersion: string;
}) {
  const router = useRouter();
  const [text, setText] = useState(initial);
  // Last server version acknowledged by a valid success response. Tracked
  // separately from the editable draft so a save started while another is
  // pending still bases its next attempt on the newest acknowledgement.
  const [version, setVersion] = useState(initialVersion);
  const [busy, setBusy] = useState(false);
  const [savedText, setSavedText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conflict, setConflict] = useState(false);
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
    // Capture the draft and its base version at submit time. Edits typed
    // while the request is pending stay in `text`; only this snapshot is
    // sent. When it succeeds, `version` advances, so the next save of a
    // newer draft already uses the acknowledgement from this one.
    const submitted = text;
    const submittedVersion = version;
    try {
      const res = await fetch("/api/readme", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ readme: submitted, expectedVersion: submittedVersion }),
      });
      let data: { error?: unknown; ok?: unknown; version?: unknown } | null = null;
      try {
        data = (await res.json()) as { error?: unknown; ok?: unknown; version?: unknown };
      } catch {
        data = null;
      }
      if (res.status === 409) {
        const message =
          data !== null &&
          typeof data.error === "string" &&
          data.error.length > 0
            ? data.error
            : "Someone else saved newer notes. Your draft was kept. Reload the saved notes to see their version.";
        // Keep the draft and the stale version untouched; recovery is the
        // explicit reload below, never an automatic one.
        setConflict(true);
        throw new Error(message);
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
      if (
        data?.ok !== true ||
        typeof data?.version !== "string" ||
        !/^[0-9a-f]{64}$/.test(data.version)
      ) {
        throw new Error("Save could not be confirmed. Refresh before retrying.");
      }
      // Record exactly what was accepted and the version that goes with it.
      // `text` is untouched here so a newer draft is never replaced by a
      // late response, and `router` refresh keeps client state (`initial`
      // and `initialVersion` are only mount values).
      setConflict(false);
      setSavedText(submitted);
      setVersion(data.version);
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

  const reloadSaved = () => {
    if (inFlightRef.current) return;
    if (
      window.confirm(
        "Reloading replaces your unsaved text with the saved notes. Continue?",
      )
    ) {
      window.location.reload();
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
        placeholder="Write installation steps, what to test, and known issues."
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
        {conflict && (
          <LiquidButton
            variant="glass"
            size="default"
            disabled={busy}
            title="Reload the saved notes (replaces your draft)"
            onClick={reloadSaved}
          >
            Reload saved notes
          </LiquidButton>
        )}
        {saved && !conflict && (
          <span role="status" className="text-[14px] text-[var(--foreground)]">
            Saved
          </span>
        )}
        {error && (
          <span role="alert" className="text-[14px] text-[var(--destructive)]">
            {error}
          </span>
        )}
      </div>
      {conflict && (
        <p className="mt-3 text-[14px] text-[var(--muted-ink)]">
          Your edits are still above. Copy any changes you want to keep before
          reloading the saved version. Cancelling keeps your draft as it is.
        </p>
      )}
    </div>
  );
}
