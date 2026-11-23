"use server";

import { revalidatePath } from "next/cache";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { uuid } from "@/lib/supervisao/modelo";

export async function alterarStatus(eventoId: string, categoria: string, acao: string) {
  if (!uuid.test(eventoId)) notFound();
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  if (user.is_anonymous) notFound();

  const { error } = await supabase.rpc("connect_supervisao_status", { p_evento_id: eventoId, p_acao: acao });
  if (error?.code === "42501") notFound();

  const caminho = `/eventos/${eventoId}/supervisao-equipe`;
  for (const destino of [caminho, `/eventos/${eventoId}`, `/eventos/${eventoId}/relatorio-operacional`, "/painel"]) {
    revalidatePath(destino);
  }
  const query = new URLSearchParams();
  if (categoria === "x1" || uuid.test(categoria)) query.set("categoria", categoria);
  query.set(error ? "erro" : "atualizado", "1");
  redirect(`${caminho}?${query}`);
}
