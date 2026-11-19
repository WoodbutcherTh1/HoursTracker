import type { LocalizedText } from "./types";

export const DEFAULT_LOCALE = "en";

// Scripts that read right-to-left. Used to set an explicit `dir` on the slide
// root so logical CSS ("start"/"end") actually flips instead of always
// resolving against the document's ltr default.
const RTL_LOCALES = ["ar", "he", "fa", "ur"];

export function isRtlLocale(locale: string): boolean {
  return RTL_LOCALES.includes(locale);
}

// CSS font-family for a locale's screenstop copy. Falls back to the editor's
// chosen screenshot font (passed in) for any locale without a dedicated face.
export function localeFontFamily(locale: string, fallback: string): string {
  switch (locale) {
    case "he":
      return "var(--font-he), var(--font-he-alt), sans-serif";
    case "ar":
      return "var(--font-ar), var(--font-ar-alt), sans-serif";
    case "th":
      return "var(--font-th), sans-serif";
    case "ru":
      return "var(--font-en), sans-serif";
    case "en":
      return '-apple-system, BlinkMacSystemFont, "SF Pro Display", var(--font-en), sans-serif';
    default:
      return fallback;
  }
}

// Read the value for `locale` from a localized field. Falls back to en, then to
// the first locale that has a non-empty value, then to empty string. Used by
// the canvas/preview/thumb so switching to a locale the user hasn't filled in
// shows the source copy instead of blanks.
export function pickText(field: LocalizedText | undefined, locale: string): string {
  if (!field) return "";
  const direct = field[locale];
  if (direct && direct.length) return direct;
  const en = field[DEFAULT_LOCALE];
  if (en && en.length) return en;
  for (const k of Object.keys(field)) {
    const v = field[k];
    if (v && v.length) return v;
  }
  return "";
}

// Replace `{locale}` placeholders in a screenshot path. Data URLs and empty
// strings pass through unchanged.
export function resolveScreenshot(path: string | undefined, locale: string): string {
  if (!path) return "";
  if (path.startsWith("data:")) return path;
  if (!path.includes("{locale}")) return path;
  return path.replace(/\{locale\}/g, locale);
}

// Convert legacy `string` headline/label fields to the per-locale shape. Safe
// to call on already-migrated data.
export function coerceLocalized(value: unknown): LocalizedText {
  if (typeof value === "string") return { [DEFAULT_LOCALE]: value };
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value).filter(([, text]) => typeof text === "string"));
  }
  return {};
}

// Set or clear the value for `locale` on a localized field. Empty values delete
// the key so the persisted JSON stays free of "" placeholders.
export function writeLocalized(
  field: LocalizedText | undefined,
  locale: string,
  value: string,
): LocalizedText {
  const next: LocalizedText = { ...(field || {}) };
  if (value.length === 0) delete next[locale];
  else next[locale] = value;
  return next;
}
