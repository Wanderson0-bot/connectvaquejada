"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function contexto(eventoId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  return supabase;
}

export async function atualizarStatusEvento(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const acao = String(formData.get("acao") ?? "");
  const supabase = await contexto(eventoId);
  const { error } = await supabase.rpc("painel_atualizar_status_evento", { p_evento_id: eventoId, p_acao: acao });
  if (error) {
    revalidatePath(`/eventos/${eventoId}`);
    redirect(`/eventos/${eventoId}?erro=status`);
  }
  revalidatePath(`/eventos/${eventoId}`);
  revalidatePath(`/painel`);
  revalidatePath(`/operacoes`);
  redirect(`/eventos/${eventoId}?sucesso=${encodeURIComponent(acao)}`);
}

export async function criarIniciarRodizio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const bois = Number(formData.get("quantidade_bois"));
  if (!Number.isSafeInteger(bois) || bois < 1) redirect(`/eventos/${eventoId}?acao=novo-rodizio&erro=rodizio`);
  const supabase = await contexto(eventoId);
  const { error } = await supabase.rpc("pista_ops_novo_rodizio", { p_evento_id: eventoId, p_categoria_id: categoriaId, p_quantidade_bois: bois });
  if (error) {
    console.error("Falha ao iniciar rodízio:", error.code, error.message);
    redirect(`/eventos/${eventoId}?acao=novo-rodizio&erro=rodizio`);
  }
  revalidatePath(`/eventos/${eventoId}`);
  revalidatePath(`/eventos/${eventoId}/pista-ops`);
  redirect(`/eventos/${eventoId}?sucesso=rodizio`);
}

export async function terminarRodizioAtual(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const supabase = await contexto(eventoId);
  const { error } = await supabase.rpc("pista_ops_terminar_rodizio", { p_evento_id: eventoId });
  if (error) {
    console.error("Falha ao terminar rodízio:", error.code, error.message);
    redirect(`/eventos/${eventoId}?erro=terminar-rodizio`);
  }
  revalidatePath(`/eventos/${eventoId}`);
  revalidatePath(`/eventos/${eventoId}/pista-ops`);
  redirect(`/eventos/${eventoId}?sucesso=terminar-rodizio`);
}
