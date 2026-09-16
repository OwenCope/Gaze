import Image from "next/image";

type Shot = {
  media: string;
  poster?: string;
  alt: string;
  eyebrow: string;
  title: string;
  body: string;
};

const shots: Shot[] = [
  {
    media: "/previews/gaze-panel-detail.mp4",
    poster: "/previews/gaze-panel-detail-poster.png",
    alt: "Website preview of the Gaze unlock panel and movement prompts",
    eyebrow: "Unlock preview",
    title: "See what Gaze is looking for.",
    body:
      "This website preview shows how the lock-screen panel guides you through the configured movement prompts before Gaze unlocks your Mac.",
  },
  {
    media: "/product/setup-how-detail.webp",
    alt: "Native setup preview explaining Gaze’s local recognition and password storage",
    eyebrow: "Your choices",
    title: "Know what you’re turning on.",
    body:
      "Setup explains what Gaze stores and how unlocking works. Choose recognition-only mode or enable automatic unlocking after reviewing the permissions.",
  },
  {
    media: "/product/setup-companion-detail.webp",
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
          <Frame media={shots[0].media} poster={shots[0].poster} alt={shots[0].alt} />
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
    <article className="flex flex-col rounded-[24px] border border-[var(--hairline)] bg-[var(--surface)] p-6 md:p-8">
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
        <Frame media={shot.media} poster={shot.poster} alt={shot.alt} embedded />
      </div>
    </article>
  );
}

function Frame({ media, poster, alt, embedded = false }: { media: string; poster?: string; alt: string; embedded?: boolean }) {
  const isVideo = media.endsWith(".mp4");

  return (
    <div className={`aspect-[16/10] overflow-hidden bg-[var(--surface)] ${embedded ? "rounded-[16px] border border-[var(--hairline)]" : "rounded-[24px] border border-[var(--hairline)] p-2 sm:p-3"}`}>
      {isVideo ? (
        <video
          src={media}
          controls
          preload="none"
          poster={poster}
          muted
          playsInline
          aria-label={alt}
          className={`h-full w-full object-contain ${embedded ? "" : "rounded-[16px]"}`}
        >
          {media.startsWith("/previews/gaze-panel-") && <track kind="captions" src="/previews/gaze-panel-preview.vtt" srcLang="en" label="Panel prompts" />}
        </video>
      ) : (
        <Image
          unoptimized
          src={media}
          alt={alt}
          width={1352}
          height={845}
          className={`h-full w-full object-contain ${embedded ? "" : "rounded-[16px]"}`}
        />
      )}
    </div>
  );
}
