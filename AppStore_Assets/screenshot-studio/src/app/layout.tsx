import type { Metadata } from "next";
import { Inter, Heebo, Assistant, Cairo, Tajawal, Noto_Sans_Thai } from "next/font/google";
import "./globals.css";

const font = Inter({ subsets: ["latin", "cyrillic"], display: "block", variable: "--font-en" });
const heebo = Heebo({ subsets: ["hebrew", "latin"], weight: ["400", "600", "700", "800"], display: "block", variable: "--font-he" });
const assistant = Assistant({ subsets: ["hebrew", "latin"], weight: ["400", "600", "700", "800"], display: "block", variable: "--font-he-alt" });
const cairo = Cairo({ subsets: ["arabic", "latin"], weight: ["400", "600", "700", "800"], display: "block", variable: "--font-ar" });
const tajawal = Tajawal({ subsets: ["arabic", "latin"], weight: ["400", "500", "700", "800"], display: "block", variable: "--font-ar-alt" });
const notoThai = Noto_Sans_Thai({ subsets: ["thai", "latin"], weight: ["400", "600", "700", "800"], display: "block", variable: "--font-th" });

export const metadata: Metadata = {
  title: "App Store Screenshots",
  description: "Design and export App Store + Google Play screenshots.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body
        className={`${font.variable} ${heebo.variable} ${assistant.variable} ${cairo.variable} ${tajawal.variable} ${notoThai.variable} ${font.className}`}
      >
        {children}
      </body>
    </html>
  );
}
