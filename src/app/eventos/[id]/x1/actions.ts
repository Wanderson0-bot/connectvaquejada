"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function back(eventId: string, categoryId: string, code?: string): never {
  const query = new URLSearchParams({ categoria: categoryId });
  if (code) query.set("erro", code);
  revalidatePath(`/eventos/${eventId}/x1`);
  redirect(`/eventos/${eventId}/x1?${query}`);
}

function errorCode(message?: string) {
  return message?.match(/X1_[A-Z_]+/)?.[0] ?? (message ? "operacao" : undefined);
}

export async function createBracket(formData: FormData) {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  const ids = formData.getAll("dupla_id").map(String);
  const bestOf = Number(formData.get("melhor_de"));
  const supabase = await createClient();
  const { error } = await supabase.rpc("x1_criar_chave", {
    p_evento_id: eventId, p_categoria_id: categoryId, p_melhor_de: bestOf, p_duplas: ids,
  });
  back(eventId, categoryId, errorCode(error?.message));
}

export async function registerBull(formData: FormData) {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  const supabase = await createClient();
  const { error } = await supabase.rpc("x1_registrar_boi_na_posicao", {
    p_confronto_id: String(formData.get("confronto_id")), p_resultado: String(formData.get("resultado")),
    p_numero: Number(formData.get("numero_boi")),
  });
  back(eventId, categoryId, errorCode(error?.message));
}

export async function requestReview(formData: FormData) {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  const supabase = await createClient();
  const { error } = await supabase.rpc("x1_solicitar_revisao_com_origem", {
    p_boi_id: String(formData.get("boi_id")),
    p_tipo: String(formData.get("tipo_solicitacao")),
    p_reclamante_dupla_id: String(formData.get("reclamante_dupla_id")),
    p_origem: "x1",
  });
  back(eventId, categoryId, errorCode(error?.message));
}

export async function decideReview(formData: FormData) {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  const supabase = await createClient();
  const { error } = await supabase.rpc("x1_decidir_revisao", {
    p_revisao_id: String(formData.get("revisao_id")),
    p_resultado: String(formData.get("resultado")),
    p_justificativa: String(formData.get("justificativa") ?? ""),
  });
  back(eventId, categoryId, errorCode(error?.message));
}
