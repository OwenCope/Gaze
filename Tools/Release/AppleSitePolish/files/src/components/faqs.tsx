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
  return (
    <section id="faq" aria-labelledby="faq-title" className="scroll-mt-20 bg-[var(--section-bg)] py-16 sm:py-24">
      <div className="site-container grid gap-8 md:grid-cols-[1fr_1.35fr] md:gap-16">
        <div>
          <h2 id="faq-title" className="site-heading">Before you install.</h2>
          <a href={DISCORD} target="_blank" rel="noreferrer" className="site-link mt-5 text-[16px]">Ask us on Discord <span aria-hidden>›</span></a>
        </div>
        <div className="border-t border-[var(--hairline)]">
          {faqs.map((item) => (
            <details key={item.id} name="gaze-faq" className="group border-b border-[var(--hairline)]">
              <summary className="flex min-h-16 cursor-pointer list-none items-center justify-between gap-6 rounded-sm py-5 text-[17px] font-medium tracking-[-0.01em] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)] [&::-webkit-details-marker]:hidden">
                {item.q}
                <svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-[var(--muted-ink)] transition-transform duration-200 group-open:rotate-45" aria-hidden><path d="M3 10h14M10 3v14" /></svg>
              </summary>
              <p className="pr-7 pb-6 text-pretty text-[16px] leading-relaxed text-[var(--muted-ink)]">{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
