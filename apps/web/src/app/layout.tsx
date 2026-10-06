import type { Metadata } from "next";
import { connection } from "next/server";
import localFont from "next/font/local";
import { SessionProvider } from "@/components/session-provider";
import { Shell } from "@/components/shell";
import "./globals.css";
import "./home.css";

const manrope = localFont({
  src: "../../public/fonts/manrope.ttf",
  display: "swap",
  variable: "--font-manrope",
  weight: "200 800",
});

export const metadata: Metadata = {
  title: "MESH — идеи находят своих людей",
  description:
    "Рабочее пространство для авторов и заказчиков. Находите проекты, создавайте вместе.",
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await connection();
  return (
    <html lang="ru" data-scroll-behavior="smooth">
      <body className={manrope.variable}>
        <SessionProvider>
          <Shell>{children}</Shell>
        </SessionProvider>
      </body>
    </html>
  );
}
