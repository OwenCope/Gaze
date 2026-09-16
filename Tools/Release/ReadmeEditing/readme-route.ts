import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { auth } from "@/auth";
import { writeReadme } from "@/lib/storage";

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
  await writeReadme(body.readme);
  revalidatePath("/testers");
  revalidatePath("/admin/readme");
  return NextResponse.json({ ok: true });
}
