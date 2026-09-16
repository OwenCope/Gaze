"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

const SHOTS = [
  { src: "/product/setup-welcome.webp", title: "Welcome", alt: "Native setup preview showing the Gaze welcome screen", width: 880, height: 660 },
  { src: "/product/setup-companion.webp", title: "Meet Gaze", alt: "Native setup preview introducing the Gaze companion", width: 880, height: 660 },
  { src: "/product/setup-how.webp", title: "How unlocking works", alt: "Native setup preview explaining how Gaze unlocks the Mac", width: 880, height: 660 },
  { src: "/product/setup-movement.webp", title: "Movement practice", alt: "Native setup preview showing a turn-left movement prompt", width: 560, height: 380 },
];

export function ScreenshotGallery() {
  const [selected, setSelected] = useState(0);
  const [expanded, setExpanded] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const shot = SHOTS[selected];

  useEffect(() => {
    if (!expanded) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = previousOverflow; };
  }, [expanded]);

  return (
    <section id="gallery" aria-labelledby="gallery-title" className="scroll-mt-20 bg-[var(--section-bg)] py-16 sm:py-24">
      <div className="site-container">
        <div className="mb-10 max-w-xl">
          <h2 id="gallery-title" className="site-heading">Get to know Gaze.</h2>
          <p className="mt-5 text-[19px] leading-relaxed text-[var(--muted-ink)]">A look inside setup, from your first launch to practicing the movement prompts.</p>
        </div>

        <figure>
          <div className="relative overflow-hidden rounded-[24px] bg-[var(--surface)] p-3 sm:p-8">
            <div className="relative aspect-[4/3] sm:aspect-[16/10]">
              <Image src={shot.src} alt={shot.alt} fill sizes="(max-width: 768px) 90vw, 1000px" className="object-contain" />
            </div>
            <button
              type="button"
              aria-label={"Enlarge " + shot.title + " preview"}
              onClick={() => {
                dialog.current?.showModal();
                setExpanded(true);
              }}
              className="absolute right-3 bottom-3 flex size-11 cursor-pointer items-center justify-center rounded-full border border-[var(--dock-edge)] bg-[var(--dock-tip)] text-[var(--dock-tip-ink)] backdrop-blur-[12px] focus-visible:outline-2 focus-visible:outline-[var(--action)] sm:right-5 sm:bottom-5"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5" />
              </svg>
            </button>
          </div>
          <figcaption className="mt-4 text-center text-[13px] text-[var(--muted-ink)]">{shot.title} · Setup preview · camera off</figcaption>
        </figure>

        <div role="group" aria-label="Choose a screenshot" className="mt-5 flex gap-2 overflow-x-auto px-1 pt-1 pb-3 sm:justify-center">
          {SHOTS.map((thumbnail, index) => (
            <button
              key={thumbnail.src}
              type="button"
              aria-pressed={selected === index}
              onClick={() => setSelected(index)}
              className={cn(
                "flex w-[96px] shrink-0 cursor-pointer flex-col items-center gap-2 rounded-[10px] p-1.5 text-[12px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]",
                selected === index ? "bg-[var(--surface)] text-[var(--foreground)] ring-1 ring-[var(--action)]" : "text-[var(--muted-ink)] hover:bg-[var(--surface)]",
              )}
            >
              <Image src={thumbnail.src} alt="" width={96} height={60} className="h-[50px] w-full rounded-[5px] object-contain" />
              <span>{thumbnail.title}</span>
            </button>
          ))}
        </div>

        <dialog
          ref={dialog}
          aria-labelledby="gallery-dialog-title"
          className="gallery-dialog"
          onClose={() => setExpanded(false)}
          onClick={(event) => { if (event.target === event.currentTarget) dialog.current?.close(); }}
        >
          <div className="mb-3 flex items-center justify-between gap-4">
            <h3 id="gallery-dialog-title" className="text-[16px] font-medium">{shot.title}</h3>
            <button type="button" aria-label="Close preview" onClick={() => dialog.current?.close()} className="flex size-11 cursor-pointer items-center justify-center rounded-full bg-[var(--section-bg)] focus-visible:outline-2 focus-visible:outline-[var(--action)]">
              <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden><path d="m5 5 10 10M15 5 5 15" /></svg>
            </button>
          </div>
          <Image src={shot.src} alt={shot.alt} width={shot.width} height={shot.height} sizes="96vw" className="max-h-[75dvh] w-full rounded-[10px] object-contain" />
        </dialog>
      </div>
    </section>
  );
}
