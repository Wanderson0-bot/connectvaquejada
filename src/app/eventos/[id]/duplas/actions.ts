"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

const statusPermitidos = new Set(["pendente", "pago", "isento"]);

export async function atualizarStatusPagamento(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const duplaId = String(formData.get("dupla_id") ?? "");
  const statusPagamento = String(formData.get("status_pagamento") ?? "");
  const motivoIsencao = String(formData.get("motivo_isencao") ?? "").trim();

  if (!eventoId || !duplaId) {
    redirect("/painel");
  }

  const lista = `/eventos/${encodeURIComponent(eventoId)}/duplas`;

  if (!statusPermitidos.has(statusPagamento)) {
    redirect(`${lista}?erro=status`);
  }

  if (statusPagamento === "isento" && !motivoIsencao) {
    redirect(`${lista}?erro=motivo`);
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { data: atualizada, error } = await supabase.rpc("painel_atualizar_pagamento", {
    p_evento_id: eventoId,
    p_inscricao_id: duplaId,
    p_status: statusPagamento,
    p_motivo: statusPagamento === "isento" ? motivoIsencao : null,
  });

  if (error || !atualizada) {
    if (error) console.error("Erro ao atualizar pagamento:", error.code, error.message);
    redirect(`${lista}?erro=inscricao`);
  }

  redirect(`${lista}?sucesso=pagamento`);
}

export async function adicionarCategoriaNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const nome = String(formData.get("nome") ?? "").trim();
  const ordem = Number(formData.get("ordem"));
  const valor = Number(formData.get("valor_inscricao"));
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;
  if (!eventoId || !nome || !Number.isInteger(ordem) || ordem < 0 || !Number.isFinite(valor) || valor < 0) redirect(`${base}?categoria=novo&erro=categoria`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { error } = await supabase.rpc("painel_criar_categoria", { p_evento_id: eventoId, p_nome: nome, p_ordem: ordem, p_valor: valor });
  if (error) {
    console.error("Erro ao criar categoria no Escritório:", error.code, error.message);
    redirect(`${base}?categoria=novo&erro=categoria`);
  }
  revalidatePath(base);
  redirect(`${base}?sucesso=categoria`);
}

export async function ocultarCategoriaNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { error } = await supabase.rpc("painel_ocultar_categoria", { p_categoria_id: categoriaId });
  if (error) {
    console.error("Erro ao ocultar categoria:", error.code, error.message);
    redirect(`${base}?erro=categoria`);
  }
  revalidatePath(base);
  redirect(`${base}?categoria=novo&sucesso=categoria-oculta`);
}

export async function editarCategoriaNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const nome = String(formData.get("nome") ?? "").trim();
  const rawOrdem = String(formData.get("ordem") ?? "").trim();
  const rawValor = String(formData.get("valor_inscricao") ?? "").trim();
  const ordem = Number(rawOrdem);
  const valor = Number(rawValor);
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;

  if (!eventoId || !categoriaId || !nome || nome.length > 100 || !rawOrdem || !Number.isInteger(ordem) || ordem < 0 || !rawValor || !Number.isFinite(valor) || valor < 0) {
    redirect(`${base}?categoria=novo&erro=categoria`);
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");

  const { error } = await supabase.rpc("painel_editar_categoria", {
    p_evento_id: eventoId,
    p_categoria_id: categoriaId,
    p_nome: nome,
    p_ordem: ordem,
    p_valor: valor,
  });
  if (error) {
    console.error("Erro ao editar categoria:", error.code, error.message);
    redirect(`${base}?categoria=novo&erro=categoria`);
  }

  revalidatePath(base);
  redirect(`${base}?categoria=novo&sucesso=categoria-editada`);
}

export async function reativarCategoriaNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;
  if (!eventoId || !categoriaId) redirect(`${base}?categoria=novo&erro=categoria`);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");

  const { error } = await supabase.rpc("painel_reativar_categoria", { p_categoria_id: categoriaId });
  if (error) {
    console.error("Erro ao reativar categoria:", error.code, error.message);
    redirect(`${base}?categoria=novo&erro=categoria`);
  }

  revalidatePath(base);
  redirect(`${base}?categoria=novo&sucesso=categoria-reativada`);
}

export async function excluirCategoriaNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;
  if (!eventoId || !categoriaId) redirect(`${base}?categoria=novo&erro=categoria`);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");

  const { error } = await supabase.rpc("painel_excluir_categoria", {
    p_evento_id: eventoId,
    p_categoria_id: categoriaId,
  });
  if (error) {
    console.error("Erro ao excluir categoria:", error.code, error.message);
    redirect(`${base}?categoria=novo&erro=${error.code === "23503" ? "categoria-em-uso" : "categoria"}`);
  }

  revalidatePath(base);
  redirect(`${base}?categoria=novo&sucesso=categoria-excluida`);
}

export async function excluirInscricaoNoEscritorio(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const duplaId = String(formData.get("dupla_id") ?? "");
  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;
  if (!eventoId || !duplaId) redirect(`${base}?erro=inscricao-excluir`);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");

  const { data: cancelada, error } = await supabase.rpc("painel_cancelar_inscricao", {
    p_evento_id: eventoId,
    p_inscricao_id: duplaId,
  });
  if (error || !cancelada) {
    if (error) console.error("Erro ao excluir inscrição no Escritório:", error.code, error.message);
    redirect(`${base}?erro=inscricao-excluir`);
  }

  revalidatePath(base);
  redirect(`${base}?sucesso=inscricao-excluida`);
}
