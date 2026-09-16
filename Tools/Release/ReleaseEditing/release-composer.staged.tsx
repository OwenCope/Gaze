"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { upload } from "@vercel/blob/client";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import type { StoredRelease } from "@/lib/store";

type Media = { src: string; alt: string; kind: "image" | "video" };

const field =
  "w-full rounded-[12px] border border-[var(--surface-edge)] bg-[var(--background)] px-3.5 py-2.5 text-[16px] text-[var(--foreground)] outline-none transition-colors placeholder:text-[var(--faint-ink)] focus:border-[var(--faint-ink)]/50";
const label = "block text-[14px] font-medium";
const hint = "mt-1.5 text-[13px] leading-relaxed text-[var(--faint-ink)]";

/**
 * Writing a release, on the site.
 *
 * Media uploads as you pick it rather than on submit, so a failed upload is
 * caught while you can still do something about it — and a large clip is not
 * silently attached to a post that then fails to save.
 *
 * The file goes from this browser straight to storage, never through the
 * server, because a Vercel function will not accept a request body over 4.5MB.
 * `/api/upload` only issues the token that permits it.
 *
 * Saving as a draft is the default action rather than publishing. The riskier
 * of two buttons should not be the one your hand goes to.
 */
function Tool({
  label,
  onClick,
  children,
}: {
  label: string;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className="flex size-7 cursor-pointer items-center justify-center rounded-[7px] text-[14px] text-[var(--muted-ink)] transition-colors hover:bg-[var(--foreground)]/[0.08] hover:text-[var(--foreground)]"
    >
      {children}
    </button>
  );
}

export function ReleaseComposer({ initial }: { initial?: StoredRelease }) {
  const router = useRouter();
  const fileInput = useRef<HTMLInputElement>(null);

  // The tag it was loaded under, kept separately. Releases are keyed by tag,
  // so renaming one replaces the old record in a single POST carrying
  // previousTag — never a save plus a separate DELETE.
  const originalTag = initial?.tag ?? null;

  // Synchronous in-flight guard shared by uploads and saves. React's disabled
  // state only lands on the next render, so rapid clicks could otherwise start
  // overlapping uploads/saves before the buttons visibly disable.
  const inFlight = useRef(false);

  const [tag, setTag] = useState(initial?.tag ?? "");
  const [name, setName] = useState(initial?.name ?? "");
  const [date, setDate] = useState(() =>
    (initial?.date ?? new Date().toISOString()).slice(0, 10),
  );
  const [body, setBody] = useState(initial?.body ?? "");
  const [contributors, setContributors] = useState(
    (initial?.contributors ?? []).join(" "),
  );
  const [prerelease, setPrerelease] = useState(Boolean(initial?.prerelease));
  const [isPrivate, setIsPrivate] = useState(Boolean(initial?.private));
  const [download, setDownload] = useState(initial?.download);
  const buildInput = useRef<HTMLInputElement>(null);
  const notes = useRef<HTMLTextAreaElement>(null);
  const [media, setMedia] = useState<Media[]>(() => [
    ...(initial?.images ?? []).map((i) => ({ ...i, kind: "image" as const })),
    ...(initial?.videos ?? []).map((src) => ({ src, alt: "", kind: "video" as const })),
  ]);
  const [busy, setBusy] = useState<null | "upload" | "save">(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const pick = async (files: FileList | null) => {
    if (!files?.length) return;
    if (inFlight.current) return;
    inFlight.current = true;
    const list = Array.from(files);
    setBusy("upload");
    setError(null);
    try {
      for (const [i, file] of list.entries()) {
        const of = list.length > 1 ? ` (${i + 1} of ${list.length})` : "";

        const blob = await upload(file.name, file, {
          access: "public",
          handleUploadUrl: "/api/upload",
          // Splits a large file into parts uploaded in parallel, and retries
          // only the part that failed. A clip should not restart from zero
          // because the wifi blinked at ninety percent.
          multipart: true,
          onUploadProgress: ({ percentage }) =>
            setProgress(`${Math.round(percentage)}%${of}`),
        });

        setMedia((m) => [
          ...m,
          {
            src: blob.url,
            alt: "",
            kind: file.type.startsWith("video/") ? "video" : "image",
          },
        ]);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      inFlight.current = false;
      setBusy(null);
      setProgress(null);
      if (fileInput.current) fileInput.current.value = "";
    }
  };

  const pickBuild = async (files: FileList | null) => {
    const file = files?.[0];
    if (!file) return;
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy("upload");
    setError(null);
    try {
      const blob = await upload(file.name, file, {
        access: "public",
        handleUploadUrl: "/api/upload",
        multipart: true,
        onUploadProgress: ({ percentage }) => setProgress(`${Math.round(percentage)}%`),
      });
      setDownload({ url: blob.url, name: file.name, size: file.size });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      inFlight.current = false;
      setBusy(null);
      setProgress(null);
      if (buildInput.current) buildInput.current.value = "";
    }
  };

  const wrap = (before: string, after = before) => {
    const el = notes.current;
    if (!el) return;
    const { selectionStart: a, selectionEnd: b, value } = el;
    const picked = value.slice(a, b) || "text";
    const next = value.slice(0, a) + before + picked + after + value.slice(b);
    setBody(next);
    // Put the selection back around the words, not after the markers, so a
    // second press toggles rather than nesting.
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(a + before.length, a + before.length + picked.length);
    });
  };

  const prefix = (mark: string) => {
    const el = notes.current;
    if (!el) return;
    const { selectionStart: a, value } = el;
    const lineStart = value.lastIndexOf("\n", a - 1) + 1;
    const next = value.slice(0, lineStart) + mark + value.slice(lineStart);
    setBody(next);
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(a + mark.length, a + mark.length);
    });
  };

  const save = async (draft: boolean) => {
    if (!tag.trim() || !name.trim()) {
      setError("A version and a title are required");
      return;
    }
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy("save");
    setError(null);
    // Stays false until the save succeeds: a failed save (including a refused
    // rename) keeps the entered text, completed uploads and the editor route.
    let saved = false;
    try {
      const res = await fetch("/api/releases", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          tag: tag.trim(),
          name: name.trim(),
          // Only when editing: the single POST atomically replaces this record.
          ...(originalTag ? { previousTag: originalTag } : {}),
          date: new Date(date).toISOString(),
          body,
          images: media.filter((m) => m.kind === "image").map(({ src, alt }) => ({ src, alt })),
          videos: media.filter((m) => m.kind === "video").map((m) => m.src),
          contributors: contributors.split(/[\s,]+/).filter(Boolean),
          prerelease,
          private: isPrivate,
          download,
          draft,
        }),
      });
      // An error page (or proxy) may answer non-JSON: surface the status
      // rather than a SyntaxError about unexpected tokens.
      let json: { error?: unknown; tag?: unknown } | null = null;
      try {
        json = (await res.json()) as { error?: unknown; tag?: unknown };
      } catch {
        json = null;
      }
      if (!res.ok) throw new Error(typeof json?.error === "string" ? json.error : `Could not save (HTTP ${res.status})`);
      if (json?.tag !== tag.trim()) throw new Error("Save could not be confirmed. Refresh before retrying.");

      saved = true;
      router.push(draft ? "/admin" : `/releases/${encodeURIComponent(tag.trim())}`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save");
    } finally {
      // Keep the guard through successful navigation, including drop events.
      if (!saved) { inFlight.current = false; setBusy(null); }
    }
  };

  return (
    <fieldset disabled={busy === "save"} className="m-0 grid min-w-0 gap-5 border-0 p-0 lg:grid-cols-[1.3fr_1fr]" aria-label="Release editor">
      <div className="space-y-5">
        <div className="rounded-[20px] panel p-7">
          <div className="grid gap-4 sm:grid-cols-[140px_1fr]">
            <div>
              <label className={label} htmlFor="tag">Version</label>
              <input
                id="tag"
                className={`${field} mt-2`}
                value={tag}
                onChange={(e) => setTag(e.target.value)}
                placeholder="v1.1"
              />
            </div>
            <div>
              <label className={label} htmlFor="name">Title</label>
              <input
                id="name"
                className={`${field} mt-2`}
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="The one where the notch got a shape"
              />
            </div>
          </div>

          <div className="mt-4 grid gap-4 sm:grid-cols-[180px_1fr]">
            <div>
              <label className={label} htmlFor="date">Date</label>
              <input
                id="date"
                type="date"
                className={`${field} mt-2`}
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
            <div className="flex flex-wrap items-end gap-x-6 gap-y-2 pb-1">
              <label className="flex cursor-pointer items-center gap-2.5 text-[15px]">
                <input
                  type="checkbox"
                  checked={prerelease}
                  onChange={(e) => setPrerelease(e.target.checked)}
                  className="size-4 accent-[#FF9500]"
                />
                Mark as a beta
              </label>
              {/* Private is not draft. A draft is unfinished and only you can
                  see it; this is finished and only testers can. */}
              <label className="flex cursor-pointer items-center gap-2.5 text-[15px]">
                <input
                  type="checkbox"
                  checked={isPrivate}
                  onChange={(e) => setIsPrivate(e.target.checked)}
                  className="size-4 accent-[var(--system-green)]"
                />
                Testers only
              </label>
            </div>
          </div>

          <div className="mt-5">
            <div className="flex items-center justify-between gap-3">
              <label className={label} htmlFor="body">Notes</label>
              <div className="flex items-center gap-0.5">
                <Tool label="Bold" onClick={() => wrap("**")}>
                  <span className="font-bold">B</span>
                </Tool>
                <Tool label="Italic" onClick={() => wrap("_")}>
                  <span className="italic font-serif">I</span>
                </Tool>
                <Tool label="Heading" onClick={() => prefix("### ")}>
                  <span className="font-semibold">H</span>
                </Tool>
                <Tool label="Bullet" onClick={() => prefix("- ")}>
                  <span>•</span>
                </Tool>
                <Tool label="Link" onClick={() => wrap("[", "](https://)")}>
                  <span className="underline">a</span>
                </Tool>
              </div>
            </div>
            <textarea
              ref={notes}
              id="body"
              rows={14}
              className={`${field} mt-2 resize-y font-[inherit] leading-relaxed`}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder={"The notch finally got the shape people kept asking for.\n\n### What changed\n\n- A floating panel shape\n- Faster enrollment\n"}
            />
            <p className={hint}>
              Markdown. The first line that isn’t a heading or a bullet becomes the
              summary on the card.
            </p>
          </div>

          <div className="mt-5">
            <label className={label} htmlFor="contributors">Credits</label>
            <input
              id="contributors"
              className={`${field} mt-2`}
              value={contributors}
              onChange={(e) => setContributors(e.target.value)}
              placeholder="cshariq DanFQ Aviorrok"
            />
            <p className={hint}>
              GitHub usernames, separated by spaces. Each becomes an avatar linking to
              their profile.
            </p>
          </div>
        </div>
      </div>

      <div className="space-y-5">
        <div className="rounded-[20px] panel p-7">
          <h2 className="text-[17px] font-semibold tracking-[-0.01em]">The build</h2>
          <p className={hint}>
            The app itself — a .dmg or a .zip. Testers download it from their page.
          </p>

          <input
            ref={buildInput}
            type="file"
            accept=".dmg,.zip,application/zip,application/x-apple-diskimage"
            className="hidden"
            onChange={(e) => void pickBuild(e.target.files)}
          />

          <div className="mt-5 flex flex-wrap items-center gap-3">
            <LiquidButton
              size="default"
              disabled={busy !== null}
              onClick={() => buildInput.current?.click()}
            >
              {download ? "Replace build" : "Attach build"}
            </LiquidButton>
            {download && (
              <span className="text-[14px] text-[var(--muted-ink)]">
                {download.name} · {Math.round(download.size / (1024 * 1024))} MB
              </span>
            )}
          </div>
        </div>

        <div className="rounded-[20px] panel p-7">
          <h2 className="text-[17px] font-semibold tracking-[-0.01em]">Pictures and clips</h2>
          <p className={hint}>
            The first image becomes the card’s cover. Up to 200MB each. MP4, WebM and MOV.
          </p>

          <input
            ref={fileInput}
            type="file"
            accept="image/*,video/mp4,video/webm,video/quicktime"
            multiple
            className="hidden"
            onChange={(e) => void pick(e.target.files)}
          />

          <div className="mt-5">
            <LiquidButton
              size="default"
              disabled={busy !== null}
              onClick={() => fileInput.current?.click()}
            >
              {busy === "upload" ? `Uploading ${progress ?? ""}`.trim() + "…" : "Add files"}
            </LiquidButton>
          </div>

          {media.length > 0 && (
            <ul className="mt-5 space-y-3">
              {media.map((m, i) => (
                <li
                  key={m.src}
                  className="flex items-start gap-3 rounded-[14px] border border-[var(--surface-edge)] p-2.5"
                >
                  {m.kind === "image" ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={m.src} alt="" width={56} height={56} className="size-14 shrink-0 rounded-[9px] object-cover" />
                  ) : (
                    <video src={m.src} className="size-14 shrink-0 rounded-[9px] object-cover" />
                  )}
                  <div className="min-w-0 flex-1">
                    <input
                      className={`${field} !py-1.5 text-[14px]`}
                      value={m.alt}
                      placeholder={m.kind === "image" ? "Describe it, for screen readers" : "Clip"}
                      onChange={(e) =>
                        setMedia((list) =>
                          list.map((x, j) => (j === i ? { ...x, alt: e.target.value } : x)),
                        )
                      }
                    />
                    {i === 0 && m.kind === "image" && (
                      <p className="mt-1.5 text-[12px] text-[var(--faint-ink)]">Cover image</p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => setMedia((list) => list.filter((_, j) => j !== i))}
                    className="shrink-0 cursor-pointer rounded-[9px] px-2 py-1 text-[13px] text-[var(--faint-ink)] transition-colors hover:text-[var(--foreground)]"
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="rounded-[20px] panel p-7">
          <AnimatePresence>
            {error && (
              <motion.p
                role="alert"
                initial={{ opacity: 0, y: -6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="mb-4 rounded-[12px] border border-[rgba(255,149,0,0.3)] bg-[rgba(255,149,0,0.06)] px-3.5 py-2.5 text-[14px] text-[#FF9500]"
              >
                {error}
              </motion.p>
            )}
          </AnimatePresence>

          {/* Draft first: the safer of two actions should be the one your hand
              goes to. */}
          <div className="flex flex-wrap gap-2.5">
            <LiquidButton size="default" disabled={busy !== null} onClick={() => void save(true)}>
              {busy === "save" ? "Saving…" : initial ? "Save as draft" : "Save as draft"}
            </LiquidButton>
            <LiquidButton
              variant="solid"
              size="default"
              disabled={busy !== null}
              onClick={() => void save(false)}
            >
              {initial ? "Save changes" : "Publish"}
            </LiquidButton>
          </div>
          <p className={hint}>
            A draft is only visible to you. Publishing puts it on /releases straight away.
          </p>
        </div>
      </div>
    </fieldset>
  );
}
