"use client";

import { useId, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import { MacbookPro } from "@/components/ui/macbook-pro";
import { NotchVideo, type NotchStyle } from "./notch-video";
import { cn } from "@/lib/utils";

/**
 * The mockup geometry with an offline animation of the production panel.
 *
 * These numbers are the mockup's own image slot, read off its 650×400 viewBox.
 */
const SLOT = { x: 74.52, y: 21.32, w: 501.22, h: 323.85 };
const BOX = { w: 650, h: 400 };

const SCREEN_RECT = {
  left: `${(SLOT.x / BOX.w) * 100}%`,
  top: `${(SLOT.y / BOX.h) * 100}%`,
  width: `${(SLOT.w / BOX.w) * 100}%`,
  height: `${(SLOT.h / BOX.h) * 100}%`,
};

const STYLES: { id: NotchStyle; label: string }[] = [
  { id: "normal", label: "Solid" },
  { id: "semiGlass", label: "Semi glass" },
];

function Segmented({ value, onChange, options, label }: {
  value: NotchStyle;
  onChange: (value: NotchStyle) => void;
  options: { id: NotchStyle; label: string }[];
  label: string;
}) {
  const id = useId();
  const reduceMotion = useReducedMotion();
  const [pointerDriven, setPointerDriven] = useState(false);

  return (
    <div role="group" aria-label={label} className="material-switch flex select-none gap-0.5 rounded-full p-1"
      onKeyDownCapture={() => setPointerDriven(false)}
      onPointerDown={(event) => setPointerDriven(event.isPrimary && event.button === 0)}>
      {options.map((option) => {
        const selected = value === option.id;
        return (
          <button key={option.id} type="button" onClick={() => onChange(option.id)}
            aria-pressed={selected}
            className={cn("relative min-h-11 cursor-pointer touch-manipulation whitespace-nowrap rounded-full px-3 py-2 text-[13px] font-medium text-[var(--foreground)] sm:px-4",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]")}>
            {selected && <motion.span aria-hidden
              layoutId={!reduceMotion && pointerDriven ? `material-${id}` : undefined}
              initial={false}
              transition={!reduceMotion && pointerDriven ? { type: "spring", duration: 0.25, bounce: 0 } : { duration: 0 }}
              className="material-selection absolute inset-0 rounded-full" />}
            <span className="relative">{option.label}</span>
          </button>
        );
      })}
      <style jsx>{`
        .material-switch {
          border: 1px solid color-mix(in srgb, var(--foreground) 12%, transparent);
          background: linear-gradient(135deg, #ffffff32, #ffffff00 55%),
            color-mix(in srgb, var(--background) 76%, transparent);
          backdrop-filter: blur(16px) saturate(1.5);
          -webkit-backdrop-filter: blur(16px) saturate(1.5);
          box-shadow: inset 0 1px 0 #ffffff60, 0 4px 16px #0000000c;
        }
        .material-switch :global(.material-selection) {
          border: 1px solid color-mix(in srgb, var(--foreground) 10%, transparent);
          background: color-mix(in srgb, var(--foreground) 8%, var(--background));
          box-shadow: inset 0 1px 0 #ffffff55, 0 1px 4px #00000012;
        }
        @media (prefers-reduced-transparency: reduce), (prefers-contrast: more) {
          .material-switch { background: var(--background); backdrop-filter: none; -webkit-backdrop-filter: none; }
          .material-switch :global(.material-selection) { border-color: currentColor; }
        }
        @media (forced-colors: active) {
          .material-switch { background: Canvas; border-color: ButtonText; }
          .material-switch :global(.material-selection) { background: Canvas; border: 2px solid Highlight; }
        }
      `}</style>
    </div>
  );
}

export function MacScreen({ interactive = false }: { interactive?: boolean }) {
  const [style, setStyle] = useState<NotchStyle>("normal");

  return (
    <div className="flex flex-col items-center gap-5">
      <div className="group relative mx-auto w-full max-w-[1000px]">
        {/* The mockup paints its screen bed with `currentColor`; it must be black,
            so nothing shows behind the footage while it loads. */}
        <MacbookPro
          width={650}
          height={400}
          className="h-auto w-full text-black drop-shadow-[0_16px_24px_rgba(0,0,0,0.12)]"
        />
        <div
          className="absolute overflow-hidden rounded-[0.8%/1.2%]"
          style={SCREEN_RECT}
        >
          <NotchVideo style={style} />


        </div>
      </div>
      {interactive && (
        <div className="flex flex-col items-center gap-3">
          <Segmented value={style} onChange={setStyle} options={STYLES} label="Preview material" />
          <p className="text-[12px] text-[var(--muted-ink)]">
            Slowed panel preview · camera off
          </p>
        </div>
      )}
    </div>
  );
}
