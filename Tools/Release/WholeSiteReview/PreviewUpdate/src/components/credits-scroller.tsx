import type { Credit } from "@/lib/credits";
import { CreditLinks, type Contributions } from "@/components/credit-links";

export function CreditsScroller({
  credits,
  contributions = {},
}: {
  credits: Credit[];
  /** Keyed by GitHub handle. Fetched on the server; absent is fine. */
  contributions?: Record<string, Contributions | null>;
}) {
  const projects = credits.filter((credit) => credit.app);
  const people = credits.filter((credit) => !credit.app);

  return (
    <div className="px-6 pb-14">
      <div className="mx-auto max-w-[1080px]">
        <section aria-labelledby="project-credits-heading">
          <h2
            id="project-credits-heading"
            className="mb-6 text-[20px] font-semibold tracking-[-0.015em]"
          >
            Projects
          </h2>
          <div>
            {projects.map((credit) => (
              <ProjectCredit
                key={credit.name}
                credit={credit}
                contributions={credit.github ? contributions[credit.github] : null}
              />
            ))}
          </div>
        </section>

        <section className="mt-12" aria-labelledby="people-credits-heading">
          <h2
            id="people-credits-heading"
            className="mb-6 text-[20px] font-semibold tracking-[-0.015em]"
          >
            People
          </h2>
          <div className="grid gap-x-12 gap-y-6 sm:grid-cols-2">
            {people.map((credit) => (
              <PersonCredit
                key={credit.name}
                credit={credit}
                contributions={credit.github ? contributions[credit.github] : null}
              />
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}

function ProjectCredit({
  credit,
  contributions,
}: {
  credit: Credit;
  contributions?: Contributions | null;
}) {
  return (
    <article className="grid gap-4 border-t border-[var(--hairline)] py-6 md:grid-cols-[280px_minmax(0,1fr)] md:gap-8">
      <div className="flex flex-wrap items-center gap-4 sm:gap-5">
        <CreditPortrait credit={credit} size="project" />
        <div className="min-w-0">
          <h3 className="text-pretty text-[24px] font-medium leading-tight tracking-[-0.02em]">
            {credit.href ? (
              <a
                href={credit.href}
                target="_blank"
                rel="noreferrer"
                className="site-link rounded-sm focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
              >
                {credit.app}
              </a>
            ) : (
              credit.app
            )}
          </h3>
          <p className="mt-1 text-[14px] leading-5 text-[var(--muted-ink)]">
            by {credit.name}
          </p>
        </div>
      </div>

      <div className="min-w-0">
        {credit.what && (
          <p className="text-[15px] leading-[1.6] text-[var(--foreground)]">
            {credit.what}
          </p>
        )}
        {credit.contribution && (
          <p className="mt-2 text-[16px] leading-[1.6] text-[var(--muted-ink)]">
            {credit.contribution}
          </p>
        )}

        <div className="mt-2">
          <CreditLinks credit={credit} contributions={contributions} />
          {credit.rightsHolder && (
            <p className="mt-5 text-[12px] leading-[1.6] text-[var(--faint-ink)]">
              All rights reserved by {credit.rightsHolder} {credit.year}
            </p>
          )}
        </div>
      </div>
    </article>
  );
}

function PersonCredit({
  credit,
  contributions,
}: {
  credit: Credit;
  contributions?: Contributions | null;
}) {
  return (
    <article className="flex flex-col border-t border-[var(--hairline)] py-5">
      <div className="flex items-center gap-4">
        <CreditPortrait credit={credit} size="person" />
        <h3 className="min-w-0 text-pretty text-[20px] font-medium leading-tight tracking-[-0.02em]">
          {credit.href ? (
            <a
              href={credit.href}
              target="_blank"
              rel="noreferrer"
              className="site-link rounded-sm focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
            >
              {credit.name}
            </a>
          ) : (
            credit.name
          )}
        </h3>
      </div>

      {credit.contribution && (
        <p className="mt-3 text-[16px] leading-[1.6] text-[var(--muted-ink)]">
          {credit.contribution}
        </p>
      )}

      <div className="mt-2 flex flex-wrap items-end gap-x-5">
        <CreditLinks credit={credit} contributions={contributions} />

        {credit.sideApp && (
          <a
            href={credit.sideApp.href}
            target="_blank"
            rel="noreferrer"
            className="mt-5 inline-flex min-h-11 items-center gap-3 rounded-lg text-[14px] font-medium text-[var(--muted-ink)] hover:text-[var(--foreground)] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={credit.sideApp.icon}
              alt=""
              width={36}
              height={36}
              className="size-9 rounded-[9px]"
            />
            {credit.sideApp.name}
          </a>
        )}
      </div>
    </article>
  );
}

function CreditPortrait({
  credit,
  size,
}: {
  credit: Credit;
  size: "project" | "person";
}) {
  const portrait =
    credit.icon ??
    (credit.github ? `https://github.com/${credit.github}.png?size=440` : undefined);
  const dimensions =
    size === "project"
      ? "size-16 rounded-[16px] text-[22px]"
      : "size-12 rounded-[12px] text-[18px]";

  if (!portrait) {
    return (
      <span
        className={`flex shrink-0 items-center justify-center bg-[var(--panel-bg)] font-semibold text-[var(--faint-ink)] ring-1 ring-inset ring-[var(--hairline)] ${dimensions}`}
        aria-hidden
      >
        {credit.name.slice(0, 1)}
      </span>
    );
  }

  const pixels = size === "project" ? 128 : 96;
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={portrait}
      alt={credit.app ? `The ${credit.app} app icon` : credit.name}
      width={pixels}
      height={pixels}
      loading="lazy"
      className={`block shrink-0 object-cover ring-1 ring-inset ring-[var(--hairline)] ${dimensions}`}
    />
  );
}
