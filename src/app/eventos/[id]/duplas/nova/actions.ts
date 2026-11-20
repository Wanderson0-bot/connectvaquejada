"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function inscreverCompetidor(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");
  const nome = String(formData.get("nome") ?? "").trim();
  const nomeCavalo = String(formData.get("nome_cavalo") ?? "").trim();
  const nomeEquipe = String(formData.get("nome_equipe") ?? "").trim();
  const rawSenhas = String(formData.get("numero_senha") ?? "").trim();
  const numeroSenhas = rawSenhas.split(",").map((senha) => senha.trim());
  const parsedSenhas = numeroSenhas.map(Number);
  const modo = String(formData.get("modo") ?? "");
  const statusPagamento = modo === "reservar" ? "pendente" : String(formData.get("status_pagamento") ?? "");
  const motivoIsencao = String(formData.get("motivo_isencao") ?? "").trim();

  const base = `/eventos/${encodeURIComponent(eventoId)}/duplas`;

  if (
    !eventoId ||
    !categoriaId ||
    !nome ||
    nome.length > 120 ||
    nomeCavalo.length > 120 ||
    nomeEquipe.length > 120 ||
    motivoIsencao.length > 500 ||
    !rawSenhas ||
    rawSenhas.length > 500 ||
    numeroSenhas.some((senha) => !/^\d+$/.test(senha)) ||
    parsedSenhas.some((senha) => !Number.isSafeInteger(senha) || senha < 1 || senha > 2147483647) ||
    new Set(parsedSenhas).size !== parsedSenhas.length ||
    !["pendente", "pago", "isento"].includes(statusPagamento) ||
    (statusPagamento === "isento" && !motivoIsencao)
  ) {
    redirect(`${base}?erro=campos`);
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { error } = await supabase.rpc("inscrever_competidor_evento_multiplas_senhas", {
    p_evento_id: eventoId,
    p_categoria_id: categoriaId,
    p_nome: nome,
    p_numeros_senha: parsedSenhas,
    p_nome_cavalo: nomeCavalo || null,
    p_nome_equipe: nomeEquipe || null,
    p_status_pagamento: statusPagamento,
    p_motivo_isencao: statusPagamento === "isento" ? motivoIsencao : null,
  });

  if (error) {
    console.error("Erro ao inscrever competidor:", error.code, error.message);
    if (error.code === "23505") {
      redirect(`${base}?erro=senha-repetida`);
    }
    redirect(`${base}?erro=cadastro`);
  }

  redirect(`/eventos/${encodeURIComponent(eventoId)}/duplas?sucesso=inscricao`);
}
