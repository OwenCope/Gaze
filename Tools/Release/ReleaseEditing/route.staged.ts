import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { releaseDownload } from "@/lib/release-download";
import { auth } from "@/auth";
import { upsert, remove, readAll, ReleaseConflictError, type StoredRelease } from "@/lib/store";

/** Every write is owner-only. The session is checked here, not trusted from the client. */
async function requireAdmin() {
  const session = await auth();
  if (!session?.user?.isAdmin) {
    return NextResponse.json({ error: "Not allowed" }, { status: 403 });
  }
  return null;
}

export async function GET() {
  const denied = await requireAdmin();
  if (denied) return denied;
  return NextResponse.json(await readAll());
}

export async function POST(req: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  let input: unknown;
  try { input = await req.json(); } catch {
    return NextResponse.json({ error: "Send a valid release document." }, { status: 400 });
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return NextResponse.json({ error: "Send a valid release document." }, { status: 400 });
  }
  const body = input as Partial<StoredRelease> & { previousTag?: unknown };
  const tag = typeof body.tag === "string" ? body.tag.trim() : "";
  const name = typeof body.name === "string" ? body.name.trim() : "";
  if (!tag || !name) {
    return NextResponse.json({ error: "A version and a title are required" }, { status: 400 });
  }

  // The tag has to be a version, because things downstream treat it as one.
  //
  // `/api/latest` sorts by it numerically to decide which release is newest, and the Mac
  // app compares it against its own bundle version to decide whether to offer an update.
  // Both read anything non-numeric as 0 — so a tag like "final" or "sept-build" silently
  // sorts as 0.0.0, and the app would either never offer it or offer it forever. Rejecting
  // it here is the only place the mistake is still cheap to fix.
  if (!/^v?\d+(\.\d+)*(-[A-Za-z0-9.]+)?$/.test(tag)) {
    return NextResponse.json(
      { error: `"${tag}" isn't a version number. Use something like 0.3 or 1.2.1.` },
      { status: 400 },
    );
  }

  // An edit carries the tag it was loaded under so a rename is one
  // conditional write. Canonicalized with the same version rule as the tag
  // itself, and never stored on the record.
  let previousTag: string | undefined;
  const rawPrevious = body.previousTag;
  if (Object.hasOwn(body, "previousTag")) {
    if (typeof rawPrevious !== "string" || !/^v?\d+(\.\d+)*(-[A-Za-z0-9.]+)?$/.test(rawPrevious.trim())) {
      return NextResponse.json({ error: "The original version must be a version number." }, { status: 400 });
    }
    previousTag = rawPrevious.trim();
  }

  const invalidText = body.body != null && typeof body.body !== "string";
  const invalidDate = body.date != null && (typeof body.date !== "string" || !Number.isFinite(Date.parse(body.date)));
  const invalidFlags = [body.draft, body.private, body.prerelease].some((value) => value != null && typeof value !== "boolean");
  const invalidStrings = [body.videos, body.contributors].some((value) => value != null &&
    (!Array.isArray(value) || !value.every((entry) => typeof entry === "string")));
  const invalidImages = body.images != null && (!Array.isArray(body.images) || !body.images.every((entry) =>
    entry && typeof entry === "object" && typeof entry.src === "string" && typeof entry.alt === "string"));
  if (invalidText || invalidDate || invalidFlags || invalidStrings || invalidImages) {
    return NextResponse.json({ error: "Check the release date, notes and attachment fields." }, { status: 400 });
  }
  const download = body.download == null ? undefined : releaseDownload(body.download);
  if (body.download != null && !download) {
    return NextResponse.json({ error: "Remove the placeholder build or attach a valid DMG or ZIP using the build uploader." }, { status: 400 });
  }

  const release: StoredRelease = {
    tag,
    name,
    date: body.date || new Date().toISOString(),
    body: body.body ?? "",
    images: body.images ?? [],
    videos: body.videos ?? [],
    contributors: (body.contributors ?? []).map((c) => c.replace(/^@/, "").trim()).filter(Boolean),
    prerelease: Boolean(body.prerelease),
    private: Boolean(body.private),
    download: download ?? undefined,
    draft: Boolean(body.draft),
  };

  try {
    await upsert(release, previousTag);
  } catch (e) {
    if (e instanceof ReleaseConflictError) {
      return NextResponse.json({ error: e.message }, { status: 409 });
    }
    throw e;
  }
  // The public pages are statically rendered, so they need telling.
  revalidatePath("/releases");
  revalidatePath(`/releases/${tag}`);
  if (previousTag && previousTag !== tag) revalidatePath(`/releases/${previousTag}`);
  return NextResponse.json(release);
}

export async function DELETE(req: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  const { searchParams } = new URL(req.url);
  const tag = searchParams.get("tag");
  if (!tag) return NextResponse.json({ error: "No tag" }, { status: 400 });

  await remove(tag);
  revalidatePath("/releases");
  return NextResponse.json({ ok: true });
}
