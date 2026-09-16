"use client";

import { useState } from "react";

const DISCORD = "https://discord.gg/BFgKT5YJH";

const faqs = [
  {
    id: "notch",
    q: "Does it need a MacBook with a notch?",
    a: "No. The panel is drawn where the notch would be, and on a machine without one it sits in the menu bar instead. What it does need is a built-in camera — so a MacBook or an iMac is fine, and a Mac mini, Studio or Pro is not.",
  },
  {
    id: "fail",
    q: "What happens if it doesn’t recognize me?",
    a: "It keeps looking, and after a few seconds it gives up quietly. Your password still works exactly as it did — Gaze never takes that away.",
  },
  {
    id: "photo",
    q: "Could someone unlock it with a photo of me?",
    a: "Possibly. Gaze uses movement prompts and spoof checks, but a regular camera can still be fooled by a photograph or replay. Your Mac password remains the fallback.",
  },
  {
    id: "offline",
    q: "Does it need an internet connection?",
    a: "Face recognition works offline and needs no Gaze account. Checking for updates or opening links uses the internet. Your face data stays on your Mac.",
  },
  {
    id: "glasses",
    q: "What about glasses, or a beard, or a haircut?",
    a: "Enroll with and without the glasses and it copes with both. Slow changes it tends to handle; if it starts hesitating, enroll again — it takes about a minute.",
  },
  {
    id: "others",
    q: "Can more than one person enroll?",
    a: "Yes — up to five faces on one Mac. Anyone not enrolled is simply asked for the password, which is what would have happened anyway.",
  },
  {
    id: "battery",
    q: "Is it going to eat my battery?",
    a: "Unlock scanning stops when your Mac unlocks. Setup, recognition tests and Passwords approvals also use the camera. If you enable walk-away locking, Gaze periodically checks the camera while your Mac is idle.",
  },
];


export function FAQs() {
  const [openId, setOpenId] = useState<string | null>(null);
  const [pointerDriven, setPointerDriven] = useState(false);

  return (
    <section id="faq" aria-labelledby="faq-title" className="scroll-mt-20 bg-[var(--section-bg)] py-16 sm:py-24">
      <div className="site-container grid gap-8 md:grid-cols-[1fr_1.35fr] md:gap-16">
        <div>
          <h2 id="faq-title" className="site-heading">Before you install.</h2>
          <a href={DISCORD} target="_blank" rel="noreferrer" className="site-link mt-5 text-[16px]">Ask us on Discord <span aria-hidden>›</span></a>
        </div>
        <div className="border-t border-[var(--hairline)]">
          <div className="faq-interactive" data-animate={pointerDriven}>
            {faqs.map((item) => {
              const open = item.id === openId;
              return (
                <div key={item.id} className="border-b border-[var(--hairline)]" data-open={open}>
                  <h3>
                    <button type="button" id={`faq-trigger-${item.id}`}
                      aria-expanded={open} aria-controls={`faq-answer-${item.id}`}
                      onClick={(event) => {
                        setPointerDriven(event.detail > 0);
                        setOpenId(open ? null : item.id);
                      }}
                      className="flex min-h-16 w-full cursor-pointer items-center justify-between gap-6 rounded-sm py-5 text-left text-[17px] font-medium tracking-[-0.01em] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]">
                      {item.q}
                      <svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5"
                        className="faq-plus shrink-0 text-[var(--muted-ink)]" aria-hidden>
                        <path d="M3 10h14M10 3v14" />
                      </svg>
                    </button>
                  </h3>
                  <div id={`faq-answer-${item.id}`} role="region" aria-labelledby={`faq-trigger-${item.id}`}
                    aria-hidden={!open} inert={!open} className="faq-answer">
                    <div className="min-h-0 overflow-hidden">
                      <p className="pr-7 pb-6 text-pretty text-[16px] leading-relaxed text-[var(--muted-ink)]">{item.a}</p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
          <noscript>
            <style>{`.faq-interactive { display: none; }`}</style>
            <dl>{faqs.map((item) => <div key={item.id} className="border-b border-[var(--hairline)] py-5">
              <dt className="text-[17px] font-medium">{item.q}</dt>
              <dd className="mt-3 text-[16px] leading-relaxed text-[var(--muted-ink)]">{item.a}</dd>
            </div>)}</dl>
          </noscript>
        </div>
        <style jsx>{`
          .faq-answer { display: grid; grid-template-rows: 0fr; opacity: 0; }
          [data-open="true"] .faq-answer { grid-template-rows: 1fr; opacity: 1; }
          [data-open="true"] .faq-plus { transform: rotate(45deg); }
          [data-animate="true"] .faq-answer {
            transition: grid-template-rows 180ms cubic-bezier(0.32,0.72,0,1), opacity 180ms ease-out;
          }
          [data-animate="true"] .faq-plus { transition: transform 180ms cubic-bezier(0.32,0.72,0,1); }
          [data-animate="true"] [data-open="true"] .faq-answer,
          [data-animate="true"] [data-open="true"] .faq-plus { transition-duration: 240ms; }
          @media (prefers-reduced-motion: reduce) {
            [data-animate="true"] .faq-answer, [data-animate="true"] .faq-plus { transition: none; }
          }
        `}</style>
      </div>
    </section>
  );
}
