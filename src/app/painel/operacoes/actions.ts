"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function iniciarOperacao(formData: FormData) {
  const nome = String(formData.get("nome") ?? "").trim();
  const formato = String(formData.get("formato_competicao") ?? "tradicional");
  if (!nome || nome.length > 120) redirect("/painel?erro=nome-operacao");
  if (!["tradicional", "tropa_de_elite"].includes(formato)) redirect("/painel?erro=formato-operacao");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: id, error } = await supabase.rpc("painel_iniciar_operacao_com_formato", {
    p_nome: nome,
    p_formato_competicao: formato,
  });
  if (error || !id) {
    if (error) console.error("Falha ao iniciar operação com formato:", error.code, error.message);
    redirect("/painel?erro=iniciar-operacao");
  }
  revalidatePath("/painel");
  redirect(`/painel?iniciada=${encodeURIComponent(String(id))}`);
}

export async function encerrarOperacao(formData: FormData) {
  const id = String(formData.get("operacao_id") ?? "");
  if (!uuid.test(id)) redirect("/painel?erro=operacao");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("painel_encerrar_operacao", { p_operacao_id: id });
  if (error || data !== true) redirect("/painel?erro=encerrar-operacao");
  revalidatePath("/painel");
  revalidatePath("/painel/dispositivos");
  redirect("/painel?encerrada=1");
}

export async function configurarMembroOperacao(formData: FormData) {
  const operacaoId = String(formData.get("operacao_id") ?? "");
  const usuarioId = String(formData.get("usuario_id") ?? "");
  const funcao = String(formData.get("funcao") ?? "");
  const ativoValue = String(formData.get("ativo") ?? "");
  if (
    !uuid.test(operacaoId) ||
    !uuid.test(usuarioId) ||
    !["organizador", "escritorio", "locutor"].includes(funcao) ||
    !["true", "false"].includes(ativoValue)
  ) {
    redirect("/painel?erro=membro");
  }

  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) redirect("/");

  const ativo = ativoValue === "true";
  const { data, error } = await supabase.rpc("pista_ops_configurar_membro", {
    p_evento_id: operacaoId,
    p_usuario_id: usuarioId,
    p_funcao: funcao,
    p_ativo: ativo,
  });
  if (error || typeof data !== "string" || !uuid.test(data)) {
    if (error) console.error("Falha ao configurar membro da operação:", error.code, error.message);
    const errorKey = error?.message.includes("PISTA_MEMBER_PARK_MISMATCH")
      ? "membro-parque"
      : error?.message.includes("PISTA_ACTIVE_MEMBER_NOT_FOUND")
        ? "membro-inexistente"
        : "membro";
    redirect(`/painel?erro=${errorKey}`);
  }

  revalidatePath("/painel");
  revalidatePath(`/eventos/${operacaoId}/pista-ops`);
  redirect(`/painel?membro=${ativo ? "adicionado" : "revogado"}`);
}
