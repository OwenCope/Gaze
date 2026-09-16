const GROUPS = [
  {
    title: "Recognition",
    rows: [
      ["Face unlock", "Look at your Mac and it lets you in"],
      ["Movement checks", "Follow the configured prompts before unlocking"],
      ["Deliberate look", "The match has to hold, so a glance won't do it"],
      ["Up to five faces", "Every enrolled face unlocks the same Mac account"],
    ],
  },
  {
    title: "On your machine",
    rows: [
      ["On-device model", "Recognition is processed on your Mac"],
      ["No account", "Nothing to sign up for"],
      ["Local recognition", "Recognition works without a network connection"],
      ["Optional portraits", "Face-tile pictures are stored separately on your Mac"],
    ],
  },
  {
    title: "At the lock screen",
    rows: [
      ["A panel in the notch", "Appears when your Mac locks, and not before"],
      ["Touch ID still works", "Nothing is replaced or turned off"],
      ["Your password still works", "It is a faster way in, not the only way"],
      ["Three panel styles", "The Mac app offers Solid, Semi-glass, and Liquid Glass; this preview shows Solid and Semi-glass"],
    ],
  },
  {
    title: "Kept honest",
    rows: [
      ["Secure Enclave key", "Your password is encrypted with a key from this Mac"],
      ["Revoke access", "Remove the saved password after authorization"],
      ["Spoof checks", "Add hurdles but can still be fooled"],
      ["Open source", "Every line is readable"],
    ],
  },
];

export function FeatureList() {
  return (
    <section id="features" className="scroll-mt-20 px-6 pb-8 pt-16">
      <div className="mx-auto max-w-[1080px]">
        <p className="text-[13px] font-medium uppercase tracking-[0.08em] text-[var(--faint-ink)]">
          Feature list
        </p>
        <h2 className="mt-4 max-w-[18ch] text-balance text-[clamp(2rem,4.5vw,3.25rem)] font-bold leading-[1.06] tracking-[-0.035em]">
          The details, in one place.
        </h2>
        <p className="mt-5 max-w-2xl text-[17px] leading-relaxed text-[var(--muted-ink)]">
          Recognition stays local. Unlocking still depends on the protections and account already on your Mac.
        </p>
      </div>
      <div className="mx-auto mt-12 grid max-w-[1080px] gap-x-16 gap-y-14 md:grid-cols-2">
        {GROUPS.map((group) => (
          <div key={group.title}>
            <h2 className="text-[13px] font-medium uppercase tracking-[0.08em] text-[var(--faint-ink)]">
              {group.title}
            </h2>
            <dl className="mt-4 border-t border-[var(--hairline)]">
              {group.rows.map(([name, detail]) => (
                <div
                  key={name}
                  className="flex flex-col gap-1 border-b border-[var(--hairline)] py-3.5 sm:flex-row sm:items-baseline sm:gap-6"
                >
                  <dt className="text-[15px] font-medium sm:w-[42%] sm:shrink-0">{name}</dt>
                  <dd className="text-[15px] leading-snug text-[var(--muted-ink)]">{detail}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </div>
    </section>
  );
}
