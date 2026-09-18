import Image from "next/image";

type Shot = {
  media: string;
  width: number;
  height: number;
  poster?: string;
  alt: string;
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
    title: "At the lock screen",
    body:
      "Gaze checks your face, then guides you through the configured movement prompts.",
  },
  {
    media: "/product/setup-how-detail.webp",
    width: 1200,
    height: 765,
    alt: "Native setup preview explaining Gaze’s local recognition and password storage",
    title: "Choose how to use Gaze",
    body:
      "Use recognition-only mode, or enable automatic unlocking after reviewing camera and Accessibility access.",
  },
  {
    media: "/product/setup-companion-detail.webp",
    width: 1420,
    height: 700,
    alt: "Native preview of Gaze’s companion introduction during setup",
    title: "Practice before unlocking",
    body:
      "Try the movement prompts during setup before using them at the lock screen.",
  },
];

export function ProductTour() {
  return (
    <section id="tour" className="scroll-mt-20 px-6 pb-16 pt-2">
      <div className="mx-auto max-w-[1080px]">
        <article className="grid items-center gap-6 lg:grid-cols-[minmax(0,1.55fr)_minmax(0,1fr)] lg:gap-10">
          <div className="min-w-0">
            <Media shot={shots[0]} />
          </div>
          <div className="min-w-0">
            <h2 className="max-w-[20ch] text-balance text-[clamp(1.5rem,3vw,2rem)] font-medium leading-tight tracking-[-0.02em]">
              {shots[0].title}
            </h2>
            <p className="mt-3 max-w-lg text-base leading-relaxed text-[var(--muted-ink)]">
              {shots[0].body}
            </p>
          </div>
        </article>

        <div className="mt-12 grid gap-8 md:grid-cols-2">
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
        <h2 className="text-balance text-[28px] font-medium leading-tight tracking-[-0.02em]">
          {shot.title}
        </h2>
        <p className="mt-3 max-w-md text-base leading-relaxed text-[var(--muted-ink)]">
          {shot.body}
        </p>
      </div>
      <div className="mt-5">
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
        preload="metadata"
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
