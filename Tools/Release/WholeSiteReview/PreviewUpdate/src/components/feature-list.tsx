import Link from "next/link";

const DETAILS = [
  [
    "Works offline",
    "Recognition runs on your Mac. You don’t need an account to use the Mac app.",
  ],
  [
    "Up to five faces",
    "All enrolled faces unlock the same macOS account.",
  ],
  [
    "Password and Touch ID",
    "Your usual ways of signing in remain available.",
  ],
  [
    "Three panel styles",
    "Choose Solid, Semi-glass, or Liquid Glass in the Mac app.",
  ],
  [
    "Stored on your Mac",
    "Face templates and any saved login password are encrypted locally. Optional face pictures are stored separately.",
  ],
  [
    "Camera-based recognition",
    "Movement and spoof checks can still be fooled by photos or replay. They don’t provide Apple Face ID’s depth sensing.",
  ],
];

export function FeatureList() {
  return (
    <section
      id="features"
      aria-labelledby="features-title"
      className="scroll-mt-24 px-6 py-10"
    >
      <div className="mx-auto grid max-w-[1080px] gap-6 md:grid-cols-[180px_minmax(0,1fr)] md:gap-12">
        <h2
          id="features-title"
          className="text-[28px] font-medium leading-tight tracking-[-0.02em]"
        >
          Details
        </h2>
        <div>
          <dl className="grid max-w-[66ch] gap-5 text-[16px] leading-relaxed">
            {DETAILS.map(([title, description]) => (
              <div key={title}>
                <dt className="inline font-medium">{title}. </dt>
                <dd className="inline text-[var(--muted-ink)]">
                  {description}
                </dd>
              </div>
            ))}
          </dl>
          <Link href="/security" className="site-link mt-6 inline-block text-[15px]">
            Security and privacy
          </Link>
        </div>
      </div>
    </section>
  );
}
