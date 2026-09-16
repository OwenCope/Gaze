import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { auth } from "@/auth";
import { addTester, readTesters, removeTester } from "@/lib/testers";

/** Owner-only, all of it. The session is checked here, never trusted from the client. */
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
  return NextResponse.json(await readTesters());
}

export async function POST(req: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  let raw: unknown;
  try { raw = await req.json(); } catch {
    return NextResponse.json({ error: "Send valid tester details." }, { status: 400 });
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return NextResponse.json({ error: "Send valid tester details." }, { status: 400 });
  }
  const body = raw as Record<string, unknown>;
  const email = typeof body.email === "string" ? body.email.trim() : "";
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: "That doesn't look like an email" }, { status: 400 });
  }
  if ((body.github !== undefined && typeof body.github !== "string") ||
      (body.note !== undefined && typeof body.note !== "string") ||
      (body.roles !== undefined && (!Array.isArray(body.roles) || !body.roles.every((id) => typeof id === "string" && id.trim().length > 0)))) {
    return NextResponse.json({ error: "Check the tester details and selected roles." }, { status: 400 });
  }
  let list;
  try {
    list = await addTester({ email, github: body.github as string | undefined,
      note: body.note as string | undefined, roles: body.roles as string[] | undefined });
  } catch {
    return NextResponse.json({ error: "Could not save tester. Reload and try again." }, { status: 503 });
  }
  revalidatePath("/admin/testers");
  revalidatePath("/releases");
  return NextResponse.json(list);
}

export async function DELETE(req: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  const { searchParams } = new URL(req.url);
  const email = searchParams.get("email");
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    return NextResponse.json({ error: "Choose a valid tester email." }, { status: 400 });
  }
  let list;
  try { list = await removeTester(email.trim()); } catch {
    return NextResponse.json({ error: "Could not remove tester. Reload and try again." }, { status: 503 });
  }
  revalidatePath("/admin/testers");
  revalidatePath("/releases");
  return NextResponse.json(list);
}
