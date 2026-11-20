"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { validarCsvInscricoes } from "./csv";

export type ResultadoImportacaoCsv = {
  tipo: "inicial" | "sucesso" | "erro";
  mensagem: string;
  erros?: string[];
};

export async function importarInscricoesCsv(
  _resultadoAnterior: ResultadoImportacaoCsv,
  formData: FormData,
): Promise<ResultadoImportacaoCsv> {
  const eventoId = String(formData.get("evento_id") ?? "");
  const arquivo = formData.get("arquivo_csv");

  if (!/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(eventoId)) {
    return { tipo: "erro", mensagem: "Operação inválida. Atualize a página e tente novamente." };
  }
  if (!(arquivo instanceof File) || !arquivo.name.toLocaleLowerCase("pt-BR").endsWith(".csv")) {
    return { tipo: "erro", mensagem: "Selecione um arquivo CSV." };
  }
  if (arquivo.size === 0 || arquivo.size > 500_000) {
    return { tipo: "erro", mensagem: "O arquivo deve ter conteúdo e não pode ultrapassar 500 KB." };
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { tipo: "erro", mensagem: "Sua sessão expirou. Entre novamente para importar." };

  const { data: categorias, error: erroCategorias } = await supabase
    .from("categorias")
    .select("id,nome")
    .eq("evento_id", eventoId)
    .eq("ativa", true);

  if (erroCategorias) {
    console.error("Erro ao validar categorias para importação CSV:", erroCategorias.code, erroCategorias.message);
    return { tipo: "erro", mensagem: "Não foi possível validar as categorias desta operação." };
  }

  let conteudo: string;
  try {
    conteudo = new TextDecoder("utf-8", { fatal: true }).decode(await arquivo.arrayBuffer());
  } catch {
    return { tipo: "erro", mensagem: "Não foi possível ler o arquivo. Salve o CSV com codificação UTF-8." };
  }

  const validacao = validarCsvInscricoes(conteudo, categorias ?? []);
  const errosLinhas = validacao.linhas.flatMap((linha) => linha.erros.map((erro) => `Linha ${linha.linha}: ${erro}`));
  const erros = [...validacao.erros, ...errosLinhas];
  if (erros.length || !validacao.inscricoes.length) {
    return {
      tipo: "erro",
      mensagem: erros.length ? "Corrija os problemas indicados; nenhuma inscrição foi enviada." : "O arquivo não contém inscrições válidas.",
      erros: erros.slice(0, 20),
    };
  }

  const { error } = await supabase.rpc("inscrever_competidores_evento_csv", {
    p_evento_id: eventoId,
    p_inscricoes: validacao.inscricoes,
  });

  if (error) {
    console.error("Erro ao importar inscrições CSV:", error.code, error.message);
    return {
      tipo: "erro",
      mensagem: "A importação foi recusada. Nenhuma inscrição foi salva. Verifique se as senhas já estão em uso, se o evento está recebendo inscrições e se a migração de importação está aplicada.",
    };
  }

  revalidatePath(`/eventos/${eventoId}/duplas`);
  return {
    tipo: "sucesso",
    mensagem: `${validacao.inscricoes.length} inscrição(ões) importada(s) como pendente(s).`,
  };
}
