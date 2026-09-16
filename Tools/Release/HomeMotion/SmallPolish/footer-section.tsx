import type { ComponentType, ReactNode } from "react";
import Link from "next/link";
import { AppIcon } from "@/components/app-icon";

interface FooterLink {
  title: string;
  href: string;
  icon?: ComponentType<{ className?: string }>;
  external?: boolean;
}

interface FooterColumn {
  label: string;
  links: FooterLink[];
}

const FOOTER_LINK_CLASS =
  "inline-flex min-h-11 items-center gap-1 rounded-sm underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]";

function FooterLinkContent({ link }: { link: FooterLink }): ReactNode {
  return (
    <>
      {link.icon && <link.icon className="size-4" />}
      {link.title}
    </>
  );
}

export function Footer({ columns, note }: { columns: FooterColumn[]; note: string }) {
  return (
    <footer className="border-t border-[var(--hairline)] bg-[var(--section-bg)] py-12">
      <div className="site-container">
        <div className="grid gap-10 md:grid-cols-[1fr_2fr]">
          <Link
            href="/"
            aria-label="Gaze home"
            className="flex h-fit w-fit items-center gap-2 rounded-md text-[16px] font-semibold focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
          >
            <AppIcon size={48} className="size-6" />
            Gaze
          </Link>
          <nav aria-label="Footer" className="grid grid-cols-2 gap-x-8 gap-y-8 sm:grid-cols-3">
            {columns.map((section) => (
              <div key={section.label}>
                <h3 className="text-[13px] font-semibold">{section.label}</h3>
                <ul className="mt-2 text-[14px] text-[var(--muted-ink)]">
                  {section.links.map((link) => (
                    <li key={link.title}>
                      {link.external ? (
                        <a
                          href={link.href}
                          target="_blank"
                          rel="noreferrer"
                          className={FOOTER_LINK_CLASS}
                        >
                          <FooterLinkContent link={link} />
                        </a>
                      ) : (
                        <Link href={link.href} className={FOOTER_LINK_CLASS}>
                          <FooterLinkContent link={link} />
                        </Link>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </nav>
        </div>
        <p className="mt-10 border-t border-[var(--hairline)] pt-5 text-[12px] leading-relaxed text-[var(--muted-ink)]">{note}</p>
      </div>
    </footer>
  );
}
