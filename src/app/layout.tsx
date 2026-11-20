import type { Metadata } from "next";
import "./globals.css";
import styles from "./layout.module.css";
import { EstadoConexao } from "@/components/EstadoConexao";

export const metadata: Metadata = {
  title: "Connect Vaquejada",
  description: "Gestão de parques e vaquejadas",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="pt-BR" className={styles.document}>
      <body className={styles.body}><EstadoConexao />{children}</body>
    </html>
  );
}
