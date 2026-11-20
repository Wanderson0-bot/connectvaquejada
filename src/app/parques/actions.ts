"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type CadastroParqueState = { erro?: string; parqueId?: string };

export async function criarParqueNoModal(_estado: CadastroParqueState, formData: FormData): Promise<CadastroParqueState> {
  const nome = String(formData.get("nome") ?? "").trim();
  const localizacao = String(formData.get("localizacao") ?? "").trim();
  if (!nome || !localizacao) return { erro: "Preencha o nome e a localização." };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { erro: "Sua sessão expirou. Entre novamente." };
  const { data, error } = await supabase.rpc("painel_criar_parque", { p_nome: nome, p_localizacao: localizacao });
  if (error || typeof data !== "string") return { erro: "Não foi possível cadastrar o parque. Confira os dados e tente novamente." };
  return { parqueId: data };
}

export async function criarParque(formData: FormData) {
  const nome = String(formData.get("nome") ?? "").trim();
  const localizacao = String(formData.get("localizacao") ?? "").trim();
  if (!nome || !localizacao) redirect("/parques/novo?erro=campos");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data, error } = await supabase.rpc("painel_criar_parque", { p_nome: nome, p_localizacao: localizacao });
  if (error || typeof data !== "string") redirect("/parques/novo?erro=cadastro");
  redirect(`/parques/${data}`);
}

export async function criarEventoDoParque(formData: FormData) {
  const parqueId = String(formData.get("parque_id") ?? "");
  const nome = String(formData.get("nome") ?? "").trim();
  const data = String(formData.get("data") ?? "");
  const formato = String(formData.get("formato_competicao") ?? "tradicional");
  if (!parqueId || !nome || !data) redirect(`/parques/${encodeURIComponent(parqueId)}?erro=evento`);
  if (!["tradicional", "tropa_de_elite"].includes(formato)) {
    redirect(`/parques/${encodeURIComponent(parqueId)}/eventos/novo?erro=formato`);
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: id, error } = await supabase.rpc("painel_criar_evento_com_formato", {
    p_parque_id: parqueId,
    p_nome: nome,
    p_data: data,
    p_formato_competicao: formato,
  });
  if (error || typeof id !== "string") {
    if (error) console.error("Falha ao criar evento com formato:", error.code, error.message);
    redirect(`/parques/${encodeURIComponent(parqueId)}?erro=evento`);
  }
  redirect(`/eventos/${id}`);
}
