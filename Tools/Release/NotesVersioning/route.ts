import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { auth } from "@/auth";
import { ReadmeConflictError, saveReadmeDocument } from "@/lib/readme";

const EXPECTED_VERSION_RE = /^(missing|[0-9a-f]{64})$/;

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user?.isAdmin) {
    return NextResponse.json({ error: "Not allowed" }, { status: 403 });
  }

  let body: unknown;
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: "Send valid notes text." }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      !("readme" in body) || typeof body.readme !== "string") {
    return NextResponse.json({ error: "Send valid notes text." }, { status: 400 });
  }
  const record = body as { readme: string; expectedVersion?: unknown };
  if (
    typeof record.expectedVersion !== "string" ||
    !EXPECTED_VERSION_RE.test(record.expectedVersion)
  ) {
    return NextResponse.json(
      { error: "Your editor is out of date. Reload the page before saving." },
      { status: 400 },
    );
  }
  try {
    const saved = await saveReadmeDocument(record.readme, record.expectedVersion);
    revalidatePath("/testers");
    revalidatePath("/admin/readme");
    return NextResponse.json({ ok: true, version: saved.version });
  } catch (e) {
    if (e instanceof ReadmeConflictError) {
      return NextResponse.json({ error: e.message }, { status: 409 });
    }
    throw e;
  }
}
