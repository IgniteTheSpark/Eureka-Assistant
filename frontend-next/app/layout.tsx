import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Eureka 3.0",
  description: "Agentic note-taking and knowledge management",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
