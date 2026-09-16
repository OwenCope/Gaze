import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { getViewer } from "@/lib/viewer";
import { PERMISSIONS } from "@/lib/permissions";
import { readRoles, removeRole, upsertRole, type Permission } from "@/lib/roles";

/** Only someone who may manage roles, which in practice means the owner. */
async function gate() {
  const viewer = await getViewer();
  if (!viewer.can("manageRoles")) {
    return NextResponse.json({ error: "Not allowed" }, { status: 403 });
  }
  return null;
}

export async function GET() {
  const denied = await gate();
  if (denied) return denied;
  return NextResponse.json(await readRoles());
}

export async function POST(req: Request) {
  const denied = await gate();
  if (denied) return denied;

  let raw: unknown;
  try { raw = await req.json(); } catch {
    return NextResponse.json({ error: "Send valid role details." }, { status: 400 });
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return NextResponse.json({ error: "Send valid role details." }, { status: 400 });
  }
  const body = raw as Record<string, unknown>;
  if (typeof body.name !== "string" || !body.name.trim()) {
    return NextResponse.json({ error: "A name is required" }, { status: 400 });
  }
  if ((body.id !== undefined && (typeof body.id !== "string" || !body.id.trim())) ||
      (body.color !== undefined && (typeof body.color !== "string" || !/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(body.color))) ||
      (body.permissions !== undefined && (!Array.isArray(body.permissions) ||
        !body.permissions.every((permission) => typeof permission === "string" && Object.hasOwn(PERMISSIONS, permission))))) {
    return NextResponse.json({ error: "Check the role color and permissions." }, { status: 400 });
  }
  let list;
  try {
    list = await upsertRole({ id: body.id as string | undefined, name: body.name,
      color: body.color as string | undefined ?? "#34C759", permissions: body.permissions as Permission[] | undefined ?? [] });
  } catch {
    return NextResponse.json({ error: "Could not save role. Reload and try again." }, { status: 503 });
  }
  revalidatePath("/admin/testers");
  return NextResponse.json(list);
}

export async function DELETE(req: Request) {
  const denied = await gate();
  if (denied) return denied;

  const { searchParams } = new URL(req.url);
  const id = searchParams.get("id");
  if (!id?.trim()) return NextResponse.json({ error: "Choose a role to delete." }, { status: 400 });
  let list;
  try { list = await removeRole(id); } catch {
    return NextResponse.json({ error: "Could not delete role. Reload and try again." }, { status: 503 });
  }
  revalidatePath("/admin/testers");
  return NextResponse.json(list);
}
