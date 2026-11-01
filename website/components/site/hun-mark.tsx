/**
 * Hun's mark for small sizes: the app icon's switch, flat, on an ink tile.
 * The app icon itself is drawn for the Dock (padding, a dark-on-black track)
 * and turns into a dark blob below ~32px; this stays legible down to 16px.
 * The tile is a superellipse (n = 4), the smooth "squircle" of macOS icons,
 * rather than a rounded rectangle.
 */
export const HUN_MARK_TILE =
  "M24 12L23.99 14.66L23.97 15.76L23.93 16.60L23.88 17.30L23.82 17.92L23.74 18.47L23.64 18.97L23.53 19.42L23.41 19.85L23.27 20.24L23.11 20.60L22.94 20.94L22.75 21.26L22.55 21.56L22.33 21.83L22.09 22.09L21.83 22.33L21.56 22.55L21.26 22.75L20.94 22.94L20.60 23.11L20.24 23.27L19.85 23.41L19.42 23.53L18.97 23.64L18.47 23.74L17.92 23.82L17.30 23.88L16.60 23.93L15.76 23.97L14.66 23.99L12 24L9.34 23.99L8.24 23.97L7.40 23.93L6.70 23.88L6.08 23.82L5.53 23.74L5.03 23.64L4.58 23.53L4.15 23.41L3.76 23.27L3.40 23.11L3.06 22.94L2.74 22.75L2.44 22.55L2.17 22.33L1.91 22.09L1.67 21.83L1.45 21.56L1.25 21.26L1.06 20.94L0.89 20.60L0.73 20.24L0.59 19.85L0.47 19.42L0.36 18.97L0.26 18.47L0.18 17.92L0.12 17.30L0.07 16.60L0.03 15.76L0.01 14.66L0 12L0.01 9.34L0.03 8.24L0.07 7.40L0.12 6.70L0.18 6.08L0.26 5.53L0.36 5.03L0.47 4.58L0.59 4.15L0.73 3.76L0.89 3.40L1.06 3.06L1.25 2.74L1.45 2.44L1.67 2.17L1.91 1.91L2.17 1.67L2.44 1.45L2.74 1.25L3.06 1.06L3.40 0.89L3.76 0.73L4.15 0.59L4.58 0.47L5.03 0.36L5.53 0.26L6.08 0.18L6.70 0.12L7.40 0.07L8.24 0.03L9.34 0.01L12 0L14.66 0.01L15.76 0.03L16.60 0.07L17.30 0.12L17.92 0.18L18.47 0.26L18.97 0.36L19.42 0.47L19.85 0.59L20.24 0.73L20.60 0.89L20.94 1.06L21.26 1.25L21.56 1.45L21.83 1.67L22.09 1.91L22.33 2.17L22.55 2.44L22.75 2.74L22.94 3.06L23.11 3.40L23.27 3.76L23.41 4.15L23.53 4.58L23.64 5.03L23.74 5.53L23.82 6.08L23.88 6.70L23.93 7.40L23.97 8.24L23.99 9.34Z";

export function HunMark({ size = 24, className = "" }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden className={`shrink-0 ${className}`}>
      <path d={HUN_MARK_TILE} fill="#1F1B16" />
      <rect x="3.5" y="7" width="17" height="10" rx="5" fill="#F5F0E6" fillOpacity=".2" />
      <circle cx="15.5" cy="12" r="4.1" fill="#F5F0E6" />
    </svg>
  );
}
