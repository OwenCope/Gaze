import { Footer } from "@/components/ui/footer-section";

const PAGES = [
  { href: "/", title: "Overview" },
  { href: "/how-it-works", title: "How it works" },
  { href: "/features", title: "Features" },
  { href: "/security", title: "Security" },
  { href: "/releases", title: "Releases" },
  { href: "/credits", title: "Credits" },
];

export function PageLinks({ current }: { current: string }) {
  return (
    <Footer
      note="Gaze is independently developed and is not affiliated with Apple."
      columns={[
        { label: "Pages", links: PAGES.filter((page) => page.href !== current) },
        { label: "Community", links: [{ title: "Discord", href: "https://discord.gg/BFgKT5YJH", external: true }] },
      ]}
    />
  );
}
