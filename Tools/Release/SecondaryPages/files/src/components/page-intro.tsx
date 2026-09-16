import type { ReactNode } from "react";

export function PageIntro({
  eyebrow,
  title,
  description,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  children?: ReactNode;
}) {
  return (
    <header className="site-container pb-12 pt-12 sm:pb-14 sm:pt-16">
      <p className="mb-4 text-sm font-medium text-[var(--muted-ink)]">{eyebrow}</p>
      <h1 className="max-w-[22ch] text-balance text-[clamp(2.125rem,4.5vw,3.25rem)] font-semibold leading-[1.08] tracking-[-0.035em]">{title}</h1>
      <p className="mt-5 max-w-[38rem] text-[17px] leading-relaxed text-[var(--muted-ink)] sm:text-lg">{description}</p>
      {children}
    </header>
  );
}
