"use client";

import Image from "next/image";
import { useId, useRef, useState } from "react";

const steps = [
  {
    title: "Make it yours",
    label: "Enroll",
    body: "Enroll your face from a few angles, review camera access, then choose whether to enable automatic unlocking. You can finish skipped steps in Settings.",
    image: "/product/setup-welcome-detail.webp",
    alt: "Native preview of Gaze’s welcome screen during setup",
    caption: "Setup gives you control over what you enable.",
  },
  {
    title: "Lock. Look. Follow along.",
    label: "Recognize",
    body: "When automatic unlocking is enabled, Gaze opens the camera after your Mac locks. Follow the panel’s movement prompt, then return to your starting pose. Two movements are required by default.",
    image: "/previews/gaze-panel-detail-poster.png",
    video: "/previews/gaze-panel-detail.mp4",
    alt: "Simulated Gaze panel showing recognition and movement prompts",
    caption: "Simulated panel preview. Playing it does not use your camera.",
  },
  {
    title: "Back to what you were doing",
    label: "Unlock",
    body: "Once the configured recognition and movement checks pass, Gaze submits your saved Mac password and waits for macOS. Your password and Touch ID remain available. After a restart, sign in normally so Gaze can start.",
    image: "/product/setup-how-detail.webp",
    alt: "Native setup preview explaining Gaze’s local recognition and saved password",
    caption: "Setup preview. Change or revoke your saved password later in Settings.",
  },
];

export function SetupWalkthrough() {
  const [selected, setSelected] = useState(0);
  const id = useId();
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);

  return (
    <section aria-label="From setup to unlocking" className="site-container pb-20">
      <div role="tablist" aria-label="Unlocking steps" className="mb-6 grid grid-cols-3 gap-2 rounded-2xl bg-[var(--panel-bg)] p-1.5">
        {steps.map((step, index) => (
          <button
            key={step.label}
            ref={(element) => { buttons.current[index] = element; }}
            id={`${id}-tab-${index}`}
            role="tab"
            type="button"
            aria-selected={selected === index}
            aria-controls={`${id}-panel-${index}`}
            tabIndex={selected === index ? 0 : -1}
            onClick={() => setSelected(index)}
            onKeyDown={(event) => {
              let next = index;
              if (event.key === "ArrowRight") next = (index + 1) % steps.length;
              else if (event.key === "ArrowLeft") next = (index + steps.length - 1) % steps.length;
              else if (event.key === "Home") next = 0;
              else if (event.key === "End") next = steps.length - 1;
              else return;
              event.preventDefault();
              setSelected(next);
              buttons.current[next]?.focus();
            }}
            className="min-h-12 cursor-pointer rounded-xl px-2 py-3 text-sm font-medium text-[var(--muted-ink)] transition-[background-color,color,box-shadow] duration-200 aria-selected:bg-[var(--surface)] aria-selected:text-[var(--foreground)] aria-selected:shadow-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] sm:text-base"
          >
            <span aria-hidden className="mr-2 tabular-nums opacity-60">{index + 1}</span>{step.label}
          </button>
        ))}
      </div>
      {steps.map((step, index) => (
        <div
          key={step.label}
          id={`${id}-panel-${index}`}
          role="tabpanel"
          aria-labelledby={`${id}-tab-${index}`}
          hidden={selected !== index}
          tabIndex={0}
          className="walkthrough-panel focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
        >
          <div className="grid items-center gap-8 md:grid-cols-[0.8fr_1.2fr] md:gap-12">
            <div>
              <p className="mb-4 text-sm font-medium text-[var(--muted-ink)]">Step {index + 1} of 3</p>
              <h2 className="text-balance text-[clamp(1.75rem,3.5vw,2.5rem)] font-semibold leading-[1.12] tracking-[-0.03em]">{step.title}</h2>
              <p className="mt-5 text-[17px] leading-relaxed text-[var(--muted-ink)]">{step.body}</p>
            </div>
            <figure>
              <div className="aspect-[16/10]">
                {step.video && selected === index ? (
                  <video src={step.video} poster={step.image} controls muted playsInline preload="none" aria-label={step.alt} className="h-full w-full rounded-xl object-contain">
                    <track kind="captions" src="/previews/gaze-panel-preview.vtt" srcLang="en" label="Panel prompts" />
                  </video>
                ) : (
                  <Image unoptimized src={step.image} alt={step.alt} width={1352} height={845} className="h-full w-full rounded-xl object-contain" />
                )}
              </div>
              <figcaption className="mt-4 text-sm leading-relaxed text-[var(--muted-ink)]">{step.caption}</figcaption>
            </figure>
          </div>
        </div>
      ))}
    </section>
  );
}
