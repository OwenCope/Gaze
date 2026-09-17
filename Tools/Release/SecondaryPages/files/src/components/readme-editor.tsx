"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { useRouter } from "next/navigation";
import { LiquidButton } from "@/components/ui/liquid-glass-button";

type TabDraft = { schema: 1; text: string; baseVersion: string };

function parseTabDraft(raw: string): TabDraft | null {
  try {
    const draft: unknown = JSON.parse(raw);
    if (
      typeof draft !== "object" ||
      draft === null ||
      !("schema" in draft) ||
      draft.schema !== 1 ||
      !("text" in draft) ||
      typeof draft.text !== "string" ||
      !("baseVersion" in draft) ||
      typeof draft.baseVersion !== "string" ||
      !(draft.baseVersion === "missing" || (
        draft.baseVersion.length === 64 && /^[0-9a-f]{64}$/.test(draft.baseVersion)
      ))
    ) {
      return null;
    }
    return { schema: 1, text: draft.text, baseVersion: draft.baseVersion };
  } catch {
    return null;
  }
}

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
  draftKey,
}: {
  initial: string;
  initialVersion: string;
  draftKey?: string;
}) {
  const router = useRouter();
  const [initialText] = useState(initial);
  const [text, setText] = useState(initial);
  // Last server version acknowledged by a valid success response. Tracked
  // separately from the editable draft so a save started while another is
  // pending still bases its next attempt on the newest acknowledgement.
  const [version, setVersion] = useState(initialVersion);
  const [busy, setBusy] = useState(false);
  const [savedText, setSavedText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conflict, setConflict] = useState(false);
  const [recoveredDraft, setRecoveredDraft] = useState<TabDraft | null>(null);
  const [recoveryUnavailable, setRecoveryUnavailable] = useState(false);
  const liveTextRef = useRef(initial);
  const mountedRef = useRef(false);
  const recoveredDraftRef = useRef<TabDraft | null>(null);
  const storageReadyRef = useRef(false);
  const reloadConfirmedRef = useRef(false);
  // Synchronous guard: React state updates are async, so rapid clicks or a
  // click plus keyboard shortcut could otherwise send duplicate requests
  // before `busy` flips. The ref flips in the same tick as the check.
  const inFlightRef = useRef(false);

  // Saved only when the live draft still equals the text the server accepted.
  const saved = savedText !== null && text === savedText;
  const dirty = text !== (savedText ?? initialText);

  useEffect(() => {
    mountedRef.current = true;
    return () => { mountedRef.current = false; };
  }, []);

  useEffect(() => {
    if (!draftKey) return;
    const readDraft = () => {
      try {
        const raw = window.sessionStorage.getItem(draftKey);
        const draft = raw === null ? null : parseTabDraft(raw);
        if (draft && draft.text !== initialText) {
          recoveredDraftRef.current = draft;
          setRecoveredDraft(draft);
        } else if (raw !== null) {
          window.sessionStorage.removeItem(draftKey);
        }
        storageReadyRef.current = true;
      } catch {
        setRecoveryUnavailable(true);
      }
    };
    readDraft();
  }, [draftKey, initialText]);

  useEffect(() => {
    if (!dirty && !recoveredDraft) return;
    const warnBeforeUnload = (event: BeforeUnloadEvent) => {
      if (reloadConfirmedRef.current) return;
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warnBeforeUnload);
    return () => window.removeEventListener("beforeunload", warnBeforeUnload);
  }, [dirty, recoveredDraft]);

  const persistDraft = (
    nextText: string,
    baseVersion: string,
    acknowledgedText = savedText ?? initialText,
  ) => {
    if (!draftKey || !storageReadyRef.current || recoveredDraftRef.current) return;
    try {
      if (nextText === acknowledgedText) {
        window.sessionStorage.removeItem(draftKey);
      } else {
        const draft: TabDraft = { schema: 1, text: nextText, baseVersion };
        window.sessionStorage.setItem(draftKey, JSON.stringify(draft));
      }
      setRecoveryUnavailable(false);
    } catch {
      setRecoveryUnavailable(true);
    }
  };

  const restoreDraft = () => {
    if (inFlightRef.current || !recoveredDraft) return;
    liveTextRef.current = recoveredDraft.text;
    setText(recoveredDraft.text);
    setVersion(recoveredDraft.baseVersion);
    recoveredDraftRef.current = null;
    setRecoveredDraft(null);
    setConflict(false);
    setError(null);
    persistDraft(recoveredDraft.text, recoveredDraft.baseVersion);
  };

  const discardDraft = () => {
    if (inFlightRef.current || !draftKey) return;
    try {
      window.sessionStorage.removeItem(draftKey);
      setRecoveryUnavailable(false);
    } catch {
      setRecoveryUnavailable(true);
    }
    recoveredDraftRef.current = null;
    setRecoveredDraft(null);
    persistDraft(liveTextRef.current, version);
  };

  const save = async () => {
    if (inFlightRef.current || recoveredDraftRef.current) return;
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
        data.version.length !== 64 ||
        !/^[0-9a-f]{64}$/.test(data.version)
      ) {
        throw new Error("Save could not be confirmed. Refresh before retrying.");
      }
      // Record exactly what was accepted and the version that goes with it.
      // `text` is untouched here so a newer draft is never replaced by a
      // late response, and `router` refresh keeps client state (`initial`
      // and `initialVersion` are only mount values).
      if (!mountedRef.current) return;
      setConflict(false);
      setSavedText(submitted);
      setVersion(data.version);
      persistDraft(liveTextRef.current, data.version, submitted);
      router.refresh();
    } catch (e) {
      const message = e instanceof Error && e.message ? e.message : "Could not save";
      if (mountedRef.current) setError(message);
    } finally {
      inFlightRef.current = false;
      if (mountedRef.current) setBusy(false);
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
      reloadConfirmedRef.current = true;
      if (draftKey && !recoveredDraftRef.current) {
        try {
          window.sessionStorage.removeItem(draftKey);
        } catch {
          setRecoveryUnavailable(true);
        }
      }
      window.location.reload();
    }
  };

  return (
    <div className="rounded-[20px] panel p-7">
      {recoveredDraft && (
        <div className="mb-5 rounded-[12px] border border-[var(--surface-edge)] p-4">
          <p role="status" className="text-[14px] text-[var(--muted-ink)]">
            This tab has an unsaved draft. Restore it, or discard it to edit the saved notes.
          </p>
          <div className="mt-3 flex flex-wrap gap-3">
            <LiquidButton variant="glass" size="default" disabled={busy} onClick={restoreDraft}>
              Restore draft
            </LiquidButton>
            <LiquidButton variant="glass" size="default" disabled={busy} onClick={discardDraft}>
              Discard draft
            </LiquidButton>
          </div>
        </div>
      )}
      <label
        htmlFor="tester-notes"
        className="mb-2 block text-[14px] font-medium text-[var(--muted-ink)]"
      >
        Tester notes
      </label>
      <textarea
        id="tester-notes"
        disabled={recoveredDraft !== null}
        rows={20}
        value={text}
        onChange={(e) => {
          const nextText = e.target.value;
          liveTextRef.current = nextText;
          setText(nextText);
          persistDraft(nextText, version);
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
          disabled={busy || recoveredDraft !== null}
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
      {recoveryUnavailable && (
        <p role="status" className="mt-3 text-[14px] text-[var(--muted-ink)]">
          Draft recovery is unavailable in this tab. Keep a copy of unsaved changes.
        </p>
      )}
      {conflict && (
        <p className="mt-3 text-[14px] text-[var(--muted-ink)]">
          Your edits are still above. Copy any changes you want to keep before
          reloading the saved version. Cancelling keeps your draft as it is.
        </p>
      )}
    </div>
  );
}
