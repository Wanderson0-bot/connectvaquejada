import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { uuid, type DadosEvento } from "./modelo";

export async function carregarSupervisao(eventoId: string, categoriaId: string | null, relatorio = false) {
  if (!uuid.test(eventoId)) notFound();
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  if (user.is_anonymous) notFound();

  // The RPC also checks active event membership and rejects device identities.
  const { data, error } = await supabase.rpc("connect_supervisao_dados", {
    p_evento_id: eventoId, p_categoria_id: categoriaId, p_relatorio: relatorio,
  });
  if (error?.code === "42501") notFound();
  if (error || !data) throw new Error("Falha ao carregar os dados de supervisão do evento.");
  return data as DadosEvento;
}
