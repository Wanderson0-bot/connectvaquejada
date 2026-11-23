import type { Metadata } from "next";
import { cookies } from "next/headers";
import "./globals.css";
import styles from "./layout.module.css";
import { EstadoConexao } from "@/components/EstadoConexao";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Connect Vaquejada",
  description: "Gestão de parques e vaquejadas",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const store = await cookies();
  const cookiesSessao = store.getAll().map(({ name }) => name);
  const temAparelho = cookiesSessao.some((nome) => /^cv-device-auth(?:\.|$)/.test(nome));
  const temConta = cookiesSessao.some((nome) => /^sb-.+-auth-token(?:\.|$)/.test(nome));
  const { data } = temAparelho || temConta ? await (await createClient()).auth.getClaims() : { data: null };
  const tipoSessao = !data?.claims?.sub ? "visitante"
    : temAparelho ? "aparelho"
    : data.claims.is_anonymous ? "visitante" : "conta";

  return (
    <html lang="pt-BR" className={styles.document}>
      <body className={styles.body}><EstadoConexao tipoSessao={tipoSessao} />{children}</body>
    </html>
  );
}
