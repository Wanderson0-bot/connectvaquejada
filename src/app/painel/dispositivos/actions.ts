"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function gerarCodigo(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const funcao = String(formData.get("funcao") ?? "");
  const replaceId = String(formData.get("substitui_id") ?? "");
  if (!uuid.test(eventoId) || !["escritorio", "locutor", "boi_tv"].includes(funcao) || (replaceId && !uuid.test(replaceId))) redirect("/painel/dispositivos?erro=campos");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("pista_ops_mobile_code_create", {
    p_evento_id: eventoId, p_funcao: funcao, p_substitui_id: replaceId || null,
    p_minutos: Number(process.env.DEVICE_ACTIVATION_TTL_MINUTES ?? "10"),
  });
  if (error || !data?.[0]?.codigo) redirect(`/painel/dispositivos?evento=${eventoId}&erro=permissao`);
  const store = await cookies();
  store.set("cv-mobile-invite", JSON.stringify({
    evento: eventoId, codigo: data[0].codigo, expira: data[0].expira_em, funcao, substituindo: Boolean(replaceId),
  }), {
    httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "strict",
    path: "/painel/dispositivos", expires: new Date(data[0].expira_em),
  });
  redirect(`/painel/dispositivos?evento=${eventoId}&convite=1`);
}

export async function gerenciarDispositivo(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  const action = String(formData.get("acao") ?? "");
  if (!uuid.test(id) || !["bloquear", "revogar", "reativar"].includes(action)) redirect("/painel/dispositivos?erro=campos");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("pista_ops_device_manage", { p_id: id, p_action: action, p_nome: null });
  if (error || !data) redirect("/painel/dispositivos?erro=permissao");
  revalidatePath("/painel/dispositivos");
  redirect("/painel/dispositivos?atualizado=1");
}
