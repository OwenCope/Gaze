"use client";

import Image from "next/image";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { cn } from "@/lib/utils";

const SHOTS = [
  { src: "/product/setup-welcome-detail.webp", title: "Welcome", label: "Welcome", caption: "Set up recognition at your own pace.", alt: "Native setup detail showing the Gaze welcome screen", width: 1280, height: 700 },
  { src: "/product/setup-companion-detail.webp", title: "Meet Gaze", label: "Companion", caption: "Learn what the companion is asking you to do.", alt: "Native setup detail introducing the Gaze companion", width: 1420, height: 700 },
  { src: "/product/setup-how-detail.webp", title: "How unlocking works", label: "Privacy", caption: "Review local recognition and saved-password access.", alt: "Native setup detail explaining how Gaze unlocks the Mac", width: 1200, height: 765 },
  { src: "/product/setup-movement-detail.webp", title: "Movement practice", label: "Practice", caption: "Practice a movement and return to your starting pose.", alt: "Native setup detail showing a turn-left movement prompt", width: 1072, height: 481 },
];

export function ScreenshotGallery() {
  const [selected, setSelected] = useState(0);
  const [pointerSelection, setPointerSelection] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const expandButton = useRef<HTMLButtonElement>(null);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const shot = SHOTS[selected];

  useEffect(() => {
    if (!expanded) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = previousOverflow; };
  }, [expanded]);

  function selectShot(index: number, pointer: boolean) {
    setPointerSelection(pointer);
    setSelected(index);
  }

  function handleTabKeyDown(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let nextIndex: number;
    switch (event.key) {
      case "ArrowLeft": nextIndex = (index + SHOTS.length - 1) % SHOTS.length; break;
      case "ArrowRight": nextIndex = (index + 1) % SHOTS.length; break;
      case "Home": nextIndex = 0; break;
      case "End": nextIndex = SHOTS.length - 1; break;
      default: return;
    }
    event.preventDefault();
    selectShot(nextIndex, false);
    tabs.current[nextIndex]?.focus();
  }

  return (
    <section id="gallery" aria-labelledby="gallery-title" className="scroll-mt-20 bg-[var(--section-bg)] py-16 sm:py-24">
      <div className="site-container">
        <div className="grid items-center gap-7 lg:grid-cols-[minmax(0,300px)_minmax(0,710px)] lg:gap-14">
          <div>
            <h2 id="gallery-title" className="text-[32px] leading-[1.15] font-semibold tracking-[-0.025em] text-[var(--foreground)] sm:text-[36px]">Meet your guide.</h2>
            <p className="mt-5 max-w-sm text-[17px] leading-relaxed text-[var(--muted-ink)]">A familiar face, from setup to your next unlock.</p>
            <div className="mt-8 min-h-[104px] lg:mt-10">
              <h3 className="text-[20px] leading-7 font-medium text-[var(--foreground)]">{shot.title}</h3>
              <p id="gallery-shot-description" className="mt-2 max-w-sm text-[17px] leading-relaxed text-[var(--muted-ink)]">{shot.caption}</p>
            </div>
          </div>

          <div className="mx-auto w-full min-w-0 max-w-[710px]">
            <figure
              id="gallery-panel"
              role="tabpanel"
              aria-labelledby={"gallery-tab-" + selected}
              aria-describedby="gallery-shot-description"
            >
              <div className="relative aspect-[16/10] w-full overflow-hidden rounded-[20px] border border-white/10 bg-[#151518]">
                {SHOTS.map((preview, index) => (
                  <div
                    key={preview.src}
                    style={{ opacity: selected === index ? 1 : 0, transition: pointerSelection ? "opacity 400ms cubic-bezier(0.4, 0, 0.2, 1)" : "none" }}
                    aria-hidden={selected !== index}
                    className="pointer-events-none absolute inset-0 flex items-center justify-center"
                  >
                    <Image
                      unoptimized
                      loading="eager"
                      src={preview.src}
                      alt={preview.alt}
                      width={preview.width}
                      height={preview.height}
                      style={{ maxWidth: preview.width / 2 }}
                      className="block h-full w-full object-contain"
                    />
                  </div>
                ))}
                <button
                  ref={expandButton}
                  type="button"
                  aria-label={"Enlarge " + shot.title + " preview"}
                  onClick={() => {
                    dialog.current?.showModal();
                    setExpanded(true);
                  }}
                  className="absolute right-3 bottom-3 flex size-11 cursor-pointer items-center justify-center rounded-full border border-white/15 bg-[#252528] text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5" />
                  </svg>
                </button>
              </div>
              <figcaption className="mt-4 text-center text-[13px] text-[var(--muted-ink)]">Native setup detail · camera off</figcaption>
            </figure>

            <div role="tablist" aria-label="Choose a screenshot" className="relative mx-auto mt-5 grid w-full max-w-[480px] grid-cols-4 rounded-full bg-[var(--panel-bg)] p-1">
              <div
                aria-hidden
                style={{ transform: `translateX(${selected * 100}%)`, transition: pointerSelection ? "transform 380ms cubic-bezier(0.32, 0.72, 0, 1)" : "none" }}
                className="pointer-events-none absolute top-1 bottom-1 left-1 w-[calc((100%_-_8px)/4)] rounded-full bg-[var(--surface)] shadow-[0_1px_3px_rgba(0,0,0,0.08)]"
              />
              {SHOTS.map((preview, index) => (
                <button
                  key={preview.src}
                  ref={(element) => { tabs.current[index] = element; }}
                  id={"gallery-tab-" + index}
                  type="button"
                  role="tab"
                  aria-label={preview.title}
                  aria-selected={selected === index}
                  aria-controls="gallery-panel"
                  tabIndex={selected === index ? 0 : -1}
                  onClick={(event) => selectShot(index, event.detail > 0)}
                  onKeyDown={(event) => handleTabKeyDown(event, index)}
                  className={cn(
                    "relative min-h-11 min-w-0 cursor-pointer rounded-full px-1 text-[13px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] sm:text-[14px]",
                    selected === index ? "text-[var(--foreground)]" : "text-[var(--muted-ink)] hover:text-[var(--foreground)]",
                  )}
                >
                  {preview.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <dialog
          ref={dialog}
          aria-labelledby="gallery-dialog-title"
          className="gallery-dialog"
          style={{ width: `min(${shot.width / 2 + 32}px, calc(100vw - 2rem))` }}
          onClose={() => {
            setExpanded(false);
            expandButton.current?.focus();
          }}
          onClick={(event) => { if (event.target === event.currentTarget) dialog.current?.close(); }}
        >
          <div className="mb-3 flex items-center justify-between gap-4">
            <h3 id="gallery-dialog-title" className="text-[16px] font-medium">{shot.title}</h3>
            <button type="button" aria-label="Close preview" onClick={() => dialog.current?.close()} className="flex size-11 cursor-pointer items-center justify-center rounded-full bg-[var(--section-bg)] focus-visible:outline-2 focus-visible:outline-[var(--action)]">
              <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden><path d="m5 5 10 10M15 5 5 15" /></svg>
            </button>
          </div>
          <Image unoptimized src={shot.src} alt={shot.alt} width={shot.width} height={shot.height} style={{ maxWidth: shot.width / 2 }} className="mx-auto block h-auto max-h-[75dvh] w-full rounded-[10px] object-contain" />
        </dialog>
      </div>
    </section>
  );
}
