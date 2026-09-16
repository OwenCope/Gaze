import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { auth } from "@/auth";
import { getSettings, saveSettings } from "@/lib/settings";

/** Owner-only. The session is checked here, never trusted from the client. */
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
  return NextResponse.json(await getSettings());
}

export async function POST(req: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  let body: unknown;
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: "Send valid settings." }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      !("releasesRequireSignIn" in body) || typeof body.releasesRequireSignIn !== "boolean") {
    return NextResponse.json({ error: "Choose whether releases require signing in." }, { status: 400 });
  }
  let settings;
  try {
    settings = await saveSettings({ releasesRequireSignIn: body.releasesRequireSignIn });
  } catch {
    return NextResponse.json({ error: "Could not save settings. Reload and try again." }, { status: 503 });
  }
  revalidatePath("/releases");
  return NextResponse.json(settings);
}
