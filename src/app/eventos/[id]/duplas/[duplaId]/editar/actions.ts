"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function atualizarDupla(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const duplaId = String(formData.get("dupla_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const puxadorId = String(formData.get("puxador_id") ?? "");
  const numeroSenha = Number(formData.get("numero_senha"));
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas/${encodeURIComponent(duplaId)}/editar`;
  if (!eventoId || !duplaId) redirect("/painel");
  if (!categoriaId || !puxadorId || !Number.isInteger(numeroSenha) || numeroSenha < 1) redirect(`${base}?erro=campos`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data, error } = await supabase.rpc("painel_editar_inscricao", {
    p_evento_id: eventoId, p_inscricao_id: duplaId, p_categoria_id: categoriaId, p_competidor_id: puxadorId, p_numero_senha: numeroSenha,
  });
  if (error || !data) {
    if (error?.code === "23505") redirect(`${base}?erro=senha-repetida`);
    console.error("Erro ao atualizar inscrição:", error?.code, error?.message);
    redirect(`${base}?erro=cadastro`);
  }
  revalidatePath(`/eventos/${eventoId}/duplas`);
  redirect(`/eventos/${eventoId}/duplas`);
}
