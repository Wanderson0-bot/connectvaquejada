"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function sairDoAparelho() {
  const store = await cookies();
  if (store.has("cv-mobile-device")) {
    const supabase = await createClient();
    const { error } = await supabase.rpc("pista_ops_mobile_sair");
    if (error) redirect("/ativar?estado=erro-saida");
    await supabase.auth.signOut({ scope: "local" });
    for (const { name } of store.getAll()) {
      if (name.startsWith("cv-device-") || name === "cv-mobile-device") store.delete(name);
    }
  }
  redirect("/ativar?estado=saiu");
}
