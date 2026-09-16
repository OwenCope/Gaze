"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { features } from "@/lib/content";

const SHOTS: Record<string, { src: string; alt: string }> = {
  Recognition: { src: "/gallery/pane-gaze.jpg", alt: "Gaze settings showing enrolled faces" },
  "The notch panel": { src: "/gallery/pane-general.jpg", alt: "Panel shape and appearance settings" },
  "Where it keeps things": { src: "/gallery/pane-about.jpg", alt: "Information about Gaze and its recognition model" },
  "Staying out of the way": { src: "/gallery/desktop.jpg", alt: "A Mac desktop with Gaze running" },
};

export function FeaturesCarousel() {
  const track = useRef<HTMLDivElement>(null);
  const [ends, setEnds] = useState({ start: true, end: false });

  useEffect(() => {
    const scroller = track.current;
    if (!scroller) return;
    const measure = () => {
      const start = scroller.scrollLeft <= 2;
      const end = scroller.scrollLeft >= scroller.scrollWidth - scroller.clientWidth - 2;
      setEnds((previous) => previous.start === start && previous.end === end ? previous : { start, end });
    };
    const observer = new ResizeObserver(measure);
    observer.observe(scroller);
    scroller.addEventListener("scroll", measure, { passive: true });
    return () => {
      observer.disconnect();
      scroller.removeEventListener("scroll", measure);
    };
  }, []);

  const go = (direction: number, keyboard: boolean) => {
    const scroller = track.current;
    if (!scroller) return;
    const panels = scroller.querySelectorAll<HTMLElement>("article");
    if (panels.length < 2) return;
    const distance = panels[1].offsetLeft - panels[0].offsetLeft;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    scroller.scrollTo({ left: scroller.scrollLeft + direction * distance, behavior: reduce || keyboard ? "instant" : "smooth" });
  };

  return (
    <section id="features" aria-labelledby="features-title" className="scroll-mt-20 py-16 sm:py-24">
      <div className="site-container flex flex-wrap items-end justify-between gap-x-8 gap-y-3">
        <div>
          <h2 id="features-title" className="site-heading">What Gaze does.</h2>
        </div>
        <Link href="/features" className="site-link text-[17px]">Explore the features <span aria-hidden>›</span></Link>
      </div>
      <div
        ref={track}
        role="region"
        aria-label="Gaze features"
        tabIndex={0}
        onKeyDown={(event) => {
          if (event.target !== event.currentTarget || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
          switch (event.key) {
            case "ArrowLeft": go(-1, true); break;
            case "ArrowRight": go(1, true); break;
            case "Home": event.currentTarget.scrollTo({ left: 0, behavior: "instant" }); break;
            case "End": event.currentTarget.scrollTo({ left: event.currentTarget.scrollWidth, behavior: "instant" }); break;
            default: return;
          }
          event.preventDefault();
        }}
        className="no-scrollbar relative mt-10 flex snap-x snap-mandatory gap-5 overflow-x-auto px-6 pb-2 [scroll-padding-left:1.5rem] focus-visible:outline-2 focus-visible:outline-[var(--action)] lg:px-[max(1.5rem,calc((100vw-1080px)/2))] lg:[scroll-padding-left:max(1.5rem,calc((100vw-1080px)/2))]"
      >
        {features.map((feature) => {
          const shot = SHOTS[feature.title];
          return (
            <article key={feature.title} className="flex w-[min(84vw,400px)] shrink-0 snap-start flex-col overflow-hidden rounded-[24px] bg-[var(--surface)]">
              <div className="px-7 pt-8 pb-6">
                <h3 className="text-[24px] font-semibold leading-tight tracking-[-0.025em]">{feature.title}</h3>
                <p className="mt-4 text-[16px] leading-relaxed text-[var(--muted-ink)]">{feature.description}</p>
              </div>
              {shot && <div className="relative mt-auto aspect-[4/3] bg-[var(--section-bg)]"><Image src={shot.src} alt={shot.alt} fill sizes="(max-width: 480px) 84vw, 400px" className="object-contain p-4" /></div>}
            </article>
          );
        })}
      </div>
      <div className="site-container mt-5 flex justify-end gap-2">
        {[-1, 1].map((direction) => (
          <button
            key={direction}
            type="button"
            disabled={direction < 0 ? ends.start : ends.end}
            aria-label={direction < 0 ? "Previous feature" : "Next feature"}
            onClick={(event) => go(direction, event.detail === 0)}
            className="flex size-11 cursor-pointer items-center justify-center rounded-full bg-[var(--section-bg)] text-[var(--foreground)] hover:bg-[var(--hairline)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] disabled:cursor-default disabled:opacity-30"
          >
            <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d={direction < 0 ? "m14 6-6 6 6 6" : "m10 6 6 6-6 6"} />
            </svg>
          </button>
        ))}
      </div>
    </section>
  );
}
