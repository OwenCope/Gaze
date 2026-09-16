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
    media: "/features/settings-pan.mp4",
    poster: "/previews/settings-poster.png",
    alt: "Gaze Settings with stored-password controls",
    eyebrow: "Your password",
    title: "Keep control of the saved password.",
    body:
      "Gaze encrypts the saved password with a key from this Mac. After authorization, you can update it or remove it in Settings.",
  },
  {
    media: "/features/welcome.jpg",
    alt: "The Gaze setup flow",
    eyebrow: "Setup",
    title: "Set it up at your pace.",
    body:
      "Enroll your face, review permissions and choose whether Gaze may unlock this Mac. You can finish skipped steps in Settings.",
  },
];

export function ProductTour() {
  return (
    <section id="tour" className="scroll-mt-20 px-6 pb-16 pt-16">
      <div className="mx-auto max-w-[1080px]">
        <article>
          <Frame media={shots[0].media} poster={shots[0].poster} alt={shots[0].alt} />
          <div className="mt-8 grid gap-5 md:grid-cols-2 md:gap-12">
            <div>
              <p className="text-[14px] font-medium text-[var(--faint-ink)]">{shots[0].eyebrow}</p>
              <h2 className="mt-3 max-w-[16ch] text-balance text-[clamp(1.9rem,4vw,2.75rem)] font-bold leading-[1.08] tracking-[-0.03em]">
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
        <h2 className="mt-3 text-balance text-[clamp(1.75rem,3.6vw,2.5rem)] font-bold leading-[1.08] tracking-[-0.03em]">
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
