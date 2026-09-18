"use client";

import { useSession, signOut } from "next-auth/react";
import Link from "next/link";
import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";

/**
 * The account control in the floating nav.
 *
 * Deliberately quiet: signed out it is a single word, signed in it is your
 * initial. This is a page about a Mac app, not a product with accounts — the
 * control is here because the owner needs a way in, and it should not look like
 * the site wants you to sign up.
 */
export function AccountButton() {
  const { data: session, status } = useSession();
  const [open, setOpen] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const focusLast = useRef(false);
  const menuId = useId();
  const reduceMotion = useReducedMotion();
  const [me, setMe] = useState<{
    badge: string | null;
    color: string | null;
    canViewPrivate: boolean;
  } | null>(null);

  // Asked for rather than read off the session: roles change here, and a
  // session is minted at sign-in, so someone promoted this morning would wear
  // yesterday's badge until they signed out and back in.
  useEffect(() => {
    if (status !== "authenticated") return;
    let live = true;
    fetch("/api/me")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => live && setMe(d))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [status]);

  useEffect(() => {
    if (!open) return;
    const items = container.current?.querySelectorAll<HTMLElement>('[role="menuitem"]');
    if (items?.length) items[focusLast.current ? items.length - 1 : 0].focus();
    focusLast.current = false;
    const outside = (event: PointerEvent) => {
      if (event.target instanceof Node && !container.current?.contains(event.target)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);

  function handleKeys(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape" && open) {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
      trigger.current?.focus();
      return;
    }
    if (!open) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        focusLast.current = event.key === "ArrowUp";
        setOpen(true);
      }
      return;
    }
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
    const items = Array.from(event.currentTarget.querySelectorAll<HTMLElement>('[role="menuitem"]'));
    if (!items.length) return;
    event.preventDefault();
    const current = items.findIndex((item) => item === document.activeElement);
    const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1
      : (current + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
    items[next].focus();
  }

  if (status === "loading") {
    return <span className="block size-11" />;
  }

  if (!session?.user) {
    return (
      <Link
        href="/signin"
        className="flex min-h-11 cursor-pointer items-center whitespace-nowrap rounded-full px-2 text-[12px] font-medium text-[var(--muted-ink)] hover:text-[var(--foreground)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
      >
        Sign in
      </Link>
    );
  }

  const label = (session.user.name ?? session.user.email ?? "?").trim();
  const initial = label.charAt(0).toUpperCase();

  return (
    <div
      ref={container}
      className="relative"
      onKeyDown={handleKeys}
      onBlur={(event) => {
        if (!(event.relatedTarget instanceof Node) || !event.currentTarget.contains(event.relatedTarget)) setOpen(false);
      }}
    >
      <button
        ref={trigger}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        aria-label={`Account: ${label}`}
        onClick={() => setOpen((v) => !v)}
        className="flex size-11 cursor-pointer items-center justify-center rounded-full text-[13px] font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
      >
        {/* Google hands back an avatar; the initial is the fallback when a
            provider does not, or the image fails to load. */}
        {session.user.image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={session.user.image}
            alt=""
            referrerPolicy="no-referrer"
            className="size-7 rounded-full object-cover"
          />
        ) : (
          <span className="flex size-7 items-center justify-center rounded-full bg-[var(--foreground)] text-[var(--background)]">{initial}</span>
        )}
      </button>

      <AnimatePresence>
        {open && (
          <motion.div
            id={menuId}
            role="menu"
            aria-label="Account"
            initial={reduceMotion ? false : { opacity: 0, y: -4, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={reduceMotion ? undefined : { opacity: 0, y: -4, scale: 0.98 }}
            transition={{ duration: reduceMotion ? 0 : 0.16, ease: [0.32, 0.72, 0, 1] }}
            // Opaque, not the translucent `panel`.
            //
            // This menu is nested inside the dock, which has a backdrop filter of
            // its own — and a backdrop filter inside another one samples the
            // parent's already-composited layer rather than the page, so it blurs
            // nothing. `panel` is 5.5% white and was relying entirely on that blur,
            // which left the hero heading legible straight through the menu and the
            // menu's own text unreadable on top of it.
            //
            // A menu has to be readable over whatever it happens to land on, so it
            // brings its own ground instead of borrowing one.
            style={{
              background: "color-mix(in srgb, var(--background) 88%, var(--foreground))",
            }}
            className="absolute top-[calc(100%+8px)] right-0 z-50 w-56 origin-top-right rounded-[16px] border border-[var(--panel-edge)] p-2 shadow-[0_8px_24px_rgba(0,0,0,0.16)]"
          >
            <div className="flex items-center gap-2.5 px-2.5 py-2">
              {session.user.image && (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={session.user.image}
                  alt=""
                  referrerPolicy="no-referrer"
                  className="size-8 shrink-0 rounded-full object-cover"
                />
              )}
              <div className="min-w-0">
              <p className="truncate text-[14px] font-medium">{session.user.name}</p>
              <p className="truncate text-[13px] text-[var(--faint-ink)]">
                {session.user.email}
              </p>
              </div>
            </div>

            {me?.badge && (
              <p className="px-2.5 pb-2">
                <span
                  className="inline-flex items-center rounded-full px-2 py-0.5 text-[12px] font-medium"
                  style={{
                    color: me.color ?? "var(--foreground)",
                    backgroundColor: me.color
                      ? `color-mix(in srgb, ${me.color} 16%, transparent)`
                      : "var(--foreground)/0.08",
                  }}
                >
                  {me.badge}
                </span>
              </p>
            )}

            {me?.canViewPrivate && !session.user.isAdmin && (
              <Link
                href="/testers"
                role="menuitem"
                onClick={() => setOpen(false)}
                className="mt-1 block cursor-pointer rounded-[10px] px-2.5 py-2 text-[14px] transition-colors hover:bg-[var(--foreground)]/[0.06]"
              >
                Builds
              </Link>
            )}

            {session.user.isAdmin && (
              <Link
                href="/admin"
                role="menuitem"
                onClick={() => setOpen(false)}
                className="mt-1 block cursor-pointer rounded-[10px] px-2.5 py-2 text-[14px] transition-colors hover:bg-[var(--foreground)]/[0.06]"
              >
                Admin
              </Link>
            )}

            <button
              type="button"
              role="menuitem"
              onClick={() => { setOpen(false); void signOut({ callbackUrl: "/" }); }}
              className="mt-0.5 block w-full cursor-pointer rounded-[10px] px-2.5 py-2 text-left text-[14px] text-[var(--muted-ink)] transition-colors hover:bg-[var(--foreground)]/[0.06] hover:text-[var(--foreground)]"
            >
              Sign out
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
