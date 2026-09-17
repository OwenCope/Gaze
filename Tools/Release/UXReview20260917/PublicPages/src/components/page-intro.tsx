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
    <header className="site-container pb-14 pt-14 sm:pb-16 sm:pt-20">
      <p className="mb-4 text-sm font-medium text-[var(--muted-ink)]">{eyebrow}</p>
      <h1 className="max-w-[22ch] text-balance text-[clamp(2.5rem,6vw,4rem)] font-semibold leading-[1.06] tracking-[-0.035em]">{title}</h1>
      <p className="mt-5 max-w-[42ch] text-[17px] leading-[1.55] text-[var(--muted-ink)] sm:text-[19px]">{description}</p>
      {children}
    </header>
  );
}
