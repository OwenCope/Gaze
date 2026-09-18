import type { ReactNode } from "react";

export function PageIntro({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children?: ReactNode;
}) {
  return (
    <header className="site-container pb-8 pt-10 sm:pb-10 sm:pt-12">
      <h1 className="max-w-[24ch] text-balance text-[clamp(2rem,4vw,3rem)] font-semibold leading-[1.12] tracking-[-0.025em]">{title}</h1>
      <p className="mt-3 max-w-[60ch] text-base leading-relaxed text-[var(--muted-ink)] sm:text-[17px]">{description}</p>
      {children}
    </header>
  );
}
