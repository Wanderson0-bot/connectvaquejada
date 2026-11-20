"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function criarCategoria(formData: FormData) {
  const eventoId = String(formData.get("eventoId") ?? "");
  const nome = String(formData.get("nome") ?? "").trim();
  const ordemTexto = String(formData.get("ordem") ?? "0");
  const valorTexto = String(formData.get("valor_inscricao") ?? "0");

  const ordem = Number(ordemTexto);
  const valorInscricao = Number(valorTexto);

  if (
    !eventoId ||
    !nome ||
    !Number.isInteger(ordem) ||
    ordem < 0 ||
    !Number.isFinite(valorInscricao) ||
    valorInscricao < 0
  ) {
    redirect(`/eventos/${eventoId}/categorias/nova?erro=campos`);
  }

  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { error } = await supabase.rpc("painel_criar_categoria", {
    p_evento_id: eventoId,
    p_nome: nome,
    p_ordem: ordem,
    p_valor: valorInscricao,
  });

  if (error) {
    redirect(`/eventos/${eventoId}/categorias/nova?erro=cadastro`);
  }

  redirect(`/eventos/${eventoId}/categorias`);
}
