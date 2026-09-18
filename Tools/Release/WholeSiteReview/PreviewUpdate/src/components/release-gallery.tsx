"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";

interface Shot {
  src: string;
  alt: string;
}

export function ReleaseGallery({ images }: { images: Shot[] }) {
  const [open, setOpen] = useState<number | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  const opener = useRef<HTMLButtonElement>(null);
  const positionId = useId();
  const selected = open === null ? undefined : images[open];
  const isOpen = selected !== undefined;

  const close = useCallback(() => setOpen(null), []);
  const step = useCallback(
    (d: number) =>
      setOpen((i) => (i === null || images.length === 0 ? null : (i + d + images.length) % images.length)),
    [images.length],
  );

  useEffect(() => {
    const viewer = dialog.current;
    if (!isOpen || !viewer) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    viewer.showModal();
    closeButton.current?.focus();
    return () => {
      if (viewer.open) viewer.close();
      document.body.style.overflow = prev;
      if (opener.current?.isConnected) opener.current.focus({ preventScroll: true });
    };
  }, [isOpen]);

  return (
    <>
      <div className="mt-9 grid gap-4 sm:grid-cols-2">
        {images.map((img, i) => (
          <button
            key={img.src}
            type="button"
            onClick={(event) => {
              opener.current = event.currentTarget;
              setOpen(i);
            }}
            aria-label={`Open ${img.alt || `picture ${i + 1}`}`}
            className={`group block cursor-zoom-in overflow-hidden rounded-[16px] border border-[var(--surface-edge)] outline-none focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--foreground)] ${
              images.length % 2 === 1 && i === 0 ? "sm:col-span-2" : ""
            }`}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={img.src}
              alt={img.alt}
              loading={i === 0 ? "eager" : "lazy"}
              className="block w-full"
            />
          </button>
        ))}
      </div>

      <dialog
          ref={dialog}
          aria-label={selected?.alt || "Release picture"}
          aria-describedby={positionId}
          onClose={close}
          onCancel={(event) => { event.preventDefault(); close(); }}
          onClick={(event) => { if (event.target === event.currentTarget) close(); }}
          onKeyDown={(event) => {
            if (event.altKey || event.ctrlKey || event.metaKey) return;
            if (event.key === "Tab") {
              const buttons = event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not([disabled])");
              const first = buttons[0];
              const last = buttons[buttons.length - 1];
              if (event.shiftKey && document.activeElement === first) {
                event.preventDefault();
                last?.focus();
              } else if (!event.shiftKey && document.activeElement === last) {
                event.preventDefault();
                first?.focus();
              }
            }
            if (event.key === "ArrowRight") { event.preventDefault(); step(1); }
            if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); }
          }}
          className="fixed inset-0 m-0 h-dvh w-dvw max-h-none max-w-none border-0 bg-transparent p-4 text-white outline-none backdrop:bg-black/85 backdrop:backdrop-blur-sm open:flex open:items-center open:justify-center sm:p-10"
        >
        {selected && (
          <>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={selected.src}
            alt={selected.alt}
            className="max-h-full max-w-full cursor-default rounded-lg object-contain"
          />

          <button
            ref={closeButton}
            type="button"
            onClick={close}
            aria-label="Close"
            className="absolute right-4 top-4 flex size-11 items-center justify-center rounded-full border border-white/20 bg-black/60 text-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white sm:right-6 sm:top-6"
          >
            <svg viewBox="0 0 24 24" className="size-4" fill="none" aria-hidden>
              <path d="M6 6l12 12M18 6L6 18" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
          </button>

          {images.length > 1 && (
            <>
              <Step dir="prev" onClick={() => step(-1)} />
              <Step dir="next" onClick={() => step(1)} />
            </>
          )}
          <p id={positionId} className="sr-only" aria-live="polite">
            Picture {(open ?? 0) + 1} of {images.length}
          </p>
          </>
        )}
      </dialog>
    </>
  );
}

function Step({ dir, onClick }: { dir: "prev" | "next"; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={dir === "prev" ? "Previous picture" : "Next picture"}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      className={`absolute top-1/2 flex size-11 -translate-y-1/2 items-center justify-center rounded-full border border-white/20 bg-black/60 text-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white ${
        dir === "prev" ? "left-3 sm:left-6" : "right-3 sm:right-6"
      }`}
    >
      <svg viewBox="0 0 24 24" className="size-[18px]" fill="none" aria-hidden>
        <path
          d={dir === "prev" ? "M14.5 6.5 9 12l5.5 5.5" : "M9.5 6.5 15 12l-5.5 5.5"}
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  );
}
