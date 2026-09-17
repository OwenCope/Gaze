import Image from "next/image";

type Shot = {
  media: string;
  width: number;
  height: number;
  poster?: string;
  alt: string;
  eyebrow: string;
  title: string;
  body: string;
};

const shots: Shot[] = [
  {
    media: "/previews/gaze-panel-detail.mp4",
    width: 900,
    height: 560,
    poster: "/previews/gaze-panel-detail-poster.png",
    alt: "Website preview of the Gaze unlock panel and movement prompts",
    eyebrow: "Unlock preview",
    title: "See what Gaze is looking for.",
    body:
      "This website preview shows how the lock-screen panel guides you through the configured movement prompts before Gaze unlocks your Mac.",
  },
  {
    media: "/product/setup-how-detail.webp",
    width: 1200,
    height: 765,
    alt: "Native setup preview explaining Gaze’s local recognition and password storage",
    eyebrow: "Your choices",
    title: "Know what you’re turning on.",
    body:
      "Setup explains what Gaze stores and how unlocking works. Choose recognition-only mode or enable automatic unlocking after reviewing the permissions.",
  },
  {
    media: "/product/setup-companion-detail.webp",
    width: 1420,
    height: 700,
    alt: "Native preview of Gaze’s companion introduction during setup",
    eyebrow: "Setup",
    title: "Set it up at your pace.",
    body:
      "Meet the companion and practice the movements before using Gaze at the lock screen. These are previews of the current setup screens.",
  },
];

export function ProductTour() {
  return (
    <section id="tour" className="scroll-mt-20 px-6 pb-16 pt-2">
      <div className="mx-auto max-w-[1080px]">
        <article>
          <Media shot={shots[0]} />
          <div className="mt-8 grid gap-5 md:grid-cols-2 md:gap-12">
            <div>
              <p className="text-[14px] font-medium text-[var(--faint-ink)]">{shots[0].eyebrow}</p>
              <h2 className="mt-3 max-w-[16ch] text-balance text-[clamp(1.9rem,4vw,2.75rem)] font-semibold leading-[1.08] tracking-[-0.03em]">
                {shots[0].title}
              </h2>
            </div>
            <p className="max-w-lg text-[17px] leading-relaxed text-[var(--muted-ink)] md:pt-8">
              {shots[0].body}
            </p>
          </div>
        </article>

        <div className="mt-16 grid gap-8 md:grid-cols-2">
          {shots.slice(1).map((shot) => (
            <TourPanel key={shot.title} shot={shot} />
          ))}
        </div>
      </div>
    </section>
  );
}

function TourPanel({ shot }: { shot: Shot }) {
  return (
    <article className="flex min-w-0 flex-col">
      <div>
        <p className="text-[14px] font-medium text-[var(--faint-ink)]">{shot.eyebrow}</p>
        <h2 className="mt-3 text-balance text-[clamp(1.75rem,3.6vw,2.5rem)] font-semibold leading-[1.08] tracking-[-0.03em]">
          {shot.title}
        </h2>
        <p className="mt-4 max-w-md text-[16px] leading-relaxed text-[var(--muted-ink)]">
          {shot.body}
        </p>
      </div>
      <div className="mt-8">
        <Media shot={shot} />
      </div>
    </article>
  );
}

function Media({ shot }: { shot: Shot }) {
  if (shot.media.endsWith(".mp4")) {
    return (
      <video
        src={shot.media}
        width={shot.width}
        height={shot.height}
        controls
        preload="none"
        poster={shot.poster}
        muted
        playsInline
        aria-label={shot.alt}
        className="mx-auto block h-auto w-full max-w-[900px] rounded-xl"
      >
        <track kind="captions" src="/previews/gaze-panel-preview.vtt" srcLang="en" label="Panel prompts" />
      </video>
    );
  }

  return (
    <Image
      unoptimized
      src={shot.media}
      alt={shot.alt}
      width={shot.width}
      height={shot.height}
      style={{ maxWidth: shot.width / 2 }}
      className="block h-auto w-full rounded-xl"
    />
  );
}
