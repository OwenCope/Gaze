export interface Credit {
  name: string;
  /** The credited app, when applicable. */
  app?: string;
  href?: string;
  /** A short description of the credited app. */
  what?: string;
  /** How they contributed to Gaze. */
  contribution?: string;
  /** An app icon or portrait; GitHub supplies the default avatar. */
  icon?: string;
  discord?: string;
  x?: string;
  /** A verified GitHub handle. */
  github?: string;
  /** Another app made by a person credited directly. */
  sideApp?: { name: string; icon: string; href: string };
  rightsHolder?: string;
  year?: number;
}

export const credits: Credit[] = [
  {
    name: "cshariq",
    github: "cshariq",
    app: "Sapphire",
    href: "https://sapphire-app.tech",
    discord: "https://discord.gg/Ryuea8vM2h",
    what: "The notch, reimagined.",
    contribution: "Gaze’s recognition model was sourced through Sapphire.",
    icon: "/credits/sapphire.png",
    rightsHolder: "cshariq",
    year: 2026,
  },
  {
    name: "Aviorrok",
    app: "DynamicLake",
    href: "https://dynamiclake.com",
    discord: "https://discord.com/invite/Mmare6hXUd",
    x: "https://x.com/AVIROK1",
    what: "Dynamic Island for Mac.",
    contribution: "Inspired the shape of Gaze’s notch panel and the layout of its Settings window.",
    icon: "/credits/dynamiclake.png",
    rightsHolder: "Aviorrok",
    year: 2026,
  },
  {
    name: "DanFQ",
    github: "danfq",
    href: "https://github.com/danfq",
    contribution: "App ideas and thoughtful feedback throughout development.",
  },
  {
    name: "Unxnown",
    github: "UnxnownYT",
    href: "https://github.com/UnxnownYT",
    discord: "https://discord.gg/ZhBXhVVRY5",
    sideApp: {
      name: "WallX",
      icon: "/credits/wallx.png",
      href: "https://github.com/UnxnownYT/WallX",
    },
    contribution: "Set up the Discord community where early builds and feedback come together.",
  },
  {
    name: "nautey",
    contribution: "Community moderation and early testing on macOS beta releases.",
    icon: "/credits/nautey.png",
  },
  {
    name: "Vanilla",
    github: "howjin",
    icon: "/credits/vanilla.png",
    href: "https://github.com/howjin",
    contribution: "Helped develop anti-spoofing research using screen-flash liveness, parallax, and reflectance checks.",
  },
];
