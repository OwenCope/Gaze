export function LiveDemo() {
  return (
    <section id="demo" aria-labelledby="demo-title" className="scroll-mt-20 bg-[var(--section-bg)] py-16 sm:py-20">
      <div className="site-container grid items-center gap-8 lg:grid-cols-[0.8fr_1.2fr] lg:gap-12">
        <div className="space-y-5">
          <h2 id="demo-title" className="site-heading">See the panel in action.</h2>
          <p id="demo-description" className="max-w-sm text-[16px] leading-relaxed text-[var(--muted-ink)]">
            An animated preview of Gaze’s prompts. No camera is used.
          </p>
        <p id="demo-steps" className="max-w-sm text-[14px] leading-relaxed text-[var(--muted-ink)]">
          The panel opens, asks for a turn and return, then a blink. It shows “Waiting for macOS” before closing. The app supports one or two movements, and your password remains available.
        </p>
        </div>
        <video
          controls
          playsInline
          preload="none"
          poster="/previews/gaze-panel-normal-poster.png"
          aria-label="Animated preview of Gaze movement prompts and unlock feedback"
          aria-describedby="demo-description demo-steps"
          width={960}
          height={600}
          className="block aspect-[8/5] w-full rounded-[20px] bg-black object-contain"
        >
          <source src="/previews/gaze-panel-normal.mp4" type="video/mp4" />
          <track kind="captions" src="/previews/gaze-panel-preview.vtt" srcLang="en" label="Panel prompts" />
          <a href="/previews/gaze-panel-normal.mp4">Watch the panel preview</a>
        </video>

      </div>
    </section>
  );
}
