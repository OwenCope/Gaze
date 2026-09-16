import { renderMarkdown } from "./render-markdown";
import { readAll, type StoredRelease } from "./store";

export interface Contributor {
  login: string;
  avatar: string;
  url: string;
}

export interface Release {
  tag: string;
  name: string;
  date: string;
  /** Rendered HTML of the notes. */
  html: string;
  /** First line of prose, for the card. */
  excerpt: string;
  images: { src: string; alt: string }[];
  videos: string[];
  contributors: Contributor[];
  prerelease: boolean;
  draft: boolean;
  /** Testers only. */
  private: boolean;
  download?: { url: string; name: string; size: number };
}

/**
 * The card's summary: the first real sentence of the notes, as plain text.
 *
 * `*` starts a bullet only when a space follows it. Testing the character alone
 * skipped any paragraph opening with `**bold**` — the summary then jumped to
 * whichever paragraph happened not to, which is how a release led with "Delete
 * the old Face ID.app" instead of what it was about.
 *
 * The marks are then stripped rather than rendered. This lands in a `<p>` on the
 * card, so `**` left in reaches the reader as two asterisks.
 */
function summarize(body: string): string {
  const line =
    body
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l && !l.startsWith("#") && !l.startsWith("- ") && !l.startsWith("* ")) ?? "";

  return line
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1") // links and images, keeping the text
    .replace(/(\*\*|__)(.*?)\1/g, "$2") // bold
    .replace(/(\*|_)(.*?)\1/g, "$2") // italic
    .replace(/`([^`]*)`/g, "$1") // code
    .trim();
}

function toRelease(r: StoredRelease): Release {
  const excerpt = summarize(r.body);

  return {
    tag: r.tag,
    name: r.name,
    date: r.date,
    html: renderMarkdown(r.body),
    excerpt,
    images: r.images ?? [],
    videos: r.videos ?? [],
    // Credits still link to GitHub profiles — that is where these people's work
    // lives, and it is not a link to this app's own repo.
    contributors: (r.contributors ?? []).map((login) => ({
      login,
      avatar: `https://github.com/${login}.png?size=96`,
      url: `https://github.com/${login}`,
    })),
    prerelease: r.prerelease,
    draft: r.draft,
    private: Boolean(r.private),
    download: r.download,
  };
}

/**
 * Published releases, newest first.
 *
 * Private ones are filtered out unless the caller says otherwise. The default
 * is the safe one on purpose: a page that forgets to pass the flag shows less
 * than it should rather than more, and every caller here is a public page.
 */
export async function getReleases(opts?: { includePrivate?: boolean }): Promise<Release[]> {
  const all = await readAll();
  return all
    .filter((r) => !r.draft)
    .filter((r) => opts?.includePrivate || !r.private)
    .map(toRelease);
}

/** Everything including drafts — for the dashboard only. */
export async function getAllReleases(): Promise<Release[]> {
  return (await readAll()).map(toRelease);
}

export async function getRelease(
  tag: string,
  opts?: { includePrivate?: boolean },
): Promise<Release | undefined> {
  return (await getReleases(opts)).find((r) => r.tag === tag);
}
