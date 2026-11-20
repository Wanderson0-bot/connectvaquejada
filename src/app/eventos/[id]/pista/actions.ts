"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type FuncaoPista = "organizador" | "locutor";
type RpcError = { code: string; message: string } | null;
type SupabaseClient = Awaited<ReturnType<typeof createClient>>;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function route(eventoId: string, categoriaId: string) {
  return `/eventos/${encodeURIComponent(eventoId)}/pista?categoria=${encodeURIComponent(categoriaId)}`;
}

function readScope(formData: FormData) {
  const eventoId = String(formData.get("evento_id") ?? "");
  const categoriaId = String(formData.get("categoria_id") ?? "");

  if (!uuidPattern.test(eventoId) || !uuidPattern.test(categoriaId)) {
    redirect("/painel");
  }

  return { eventoId, categoriaId };
}

async function authorize(
  eventoId: string,
  categoriaId: string,
  funcoes: FuncaoPista[]
): Promise<SupabaseClient> {
  const supabase = await createClient();
  const {
    data: { user },
    error: erroUsuario,
  } = await supabase.auth.getUser();

  if (erroUsuario || !user) {
    redirect("/");
  }

  const { data: permitido, error } = await supabase.rpc("pista_tem_funcao", {
    p_evento_id: eventoId,
    p_funcoes: funcoes,
  });

  if (error) {
    console.error("Erro ao validar função da Pista:", error);
    redirect(`${route(eventoId, categoriaId)}&erro=autorizacao`);
  }

  if (!permitido) {
    redirect(`${route(eventoId, categoriaId)}&erro=acesso`);
  }

  return supabase;
}

function finish(
  eventoId: string,
  categoriaId: string,
  error: RpcError,
  success: string
): never {
  const destination = route(eventoId, categoriaId);

  if (error) {
    console.error("Falha em operação da Pista:", error);
    const reason =
      error.code === "42501"
        ? "acesso"
        : error.code === "23514" &&
            (error.message.includes("rodízio planejado") ||
              error.message.includes("próximo rodízio"))
          ? "sem-proximo"
          : error.code === "23514" &&
              error.message.includes("posição disponível")
            ? "sem-posicao"
        : error.code === "23514" || error.code === "23505"
          ? "estado"
          : error.code === "PGRST202"
            ? "rpc"
            : "operacao";
    redirect(`${destination}&erro=${reason}`);
  }

  revalidatePath(`/eventos/${eventoId}/pista`);
  redirect(`${destination}&sucesso=${success}`);
}

export async function planejarRodizio(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const quantidadeBois = Number(formData.get("quantidade_bois"));

  if (!Number.isSafeInteger(quantidadeBois) || quantidadeBois <= 0) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador"]);
  const { error } = await supabase.rpc("pista_planejar_rodizio", {
    p_evento_id: eventoId,
    p_categoria_id: categoriaId,
    p_quantidade_bois: quantidadeBois,
  });
  finish(eventoId, categoriaId, error, "planejado");
}

export async function iniciarRodizio(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const rodizioId = String(formData.get("rodizio_id") ?? "");
  const duplas = formData.getAll("dupla_ids").map(String);

  if (
    !uuidPattern.test(rodizioId) ||
    duplas.length === 0 ||
    duplas.some((id) => !uuidPattern.test(id)) ||
    new Set(duplas).size !== duplas.length
  ) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { error } = await supabase.rpc("pista_iniciar_rodizio", {
    p_rodizio_id: rodizioId,
    p_duplas: duplas,
  });
  finish(eventoId, categoriaId, error, "iniciado");
}

export async function chamarProxima(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const rodizioId = String(formData.get("rodizio_id") ?? "");

  if (!uuidPattern.test(rodizioId)) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { data, error } = await supabase.rpc("pista_chamar_proxima", {
    p_rodizio_id: rodizioId,
  });

  if (error) {
    finish(eventoId, categoriaId, error, "chamada");
  }

  revalidatePath(`/eventos/${eventoId}/pista`);
  redirect(`${route(eventoId, categoriaId)}&avanco=${data ? "chamada" : "sem-chamada"}`);
}

export async function iniciarCorrida(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const filaId = String(formData.get("fila_id") ?? "");
  const competidorId = String(formData.get("competidor_id") ?? "");

  if (!uuidPattern.test(filaId) || !uuidPattern.test(competidorId)) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { data, error } = await supabase.rpc("pista_iniciar_corrida", {
    p_fila_id: filaId,
    p_competidor_id: competidorId,
  });

  if (error) {
    finish(eventoId, categoriaId, error, "corrida");
  }

  if (data === null) {
    revalidatePath(`/eventos/${eventoId}/pista`);
    redirect(`${route(eventoId, categoriaId)}&avanco=sem-vaga`);
  }

  finish(eventoId, categoriaId, null, "corrida");
}

export async function registrarResultado(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const filaId = String(formData.get("fila_id") ?? "");
  const resultado = String(formData.get("resultado") ?? "");
  const rawPontuacao = String(formData.get("pontuacao") ?? "");
  const pontuacao = Number(rawPontuacao);

  if (resultado === "valeu_boi" && Number.isFinite(pontuacao) && pontuacao > 40) {
    redirect(`${route(eventoId, categoriaId)}&erro=pontuacao-max`);
  }

  if (
    !uuidPattern.test(filaId) ||
    !["valeu_boi", "zero"].includes(resultado) ||
    rawPontuacao.trim() === "" ||
    !Number.isFinite(pontuacao) ||
    pontuacao < 0 ||
    (resultado === "zero" && pontuacao !== 0)
  ) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { error } = await supabase.rpc("pista_registrar_resultado", {
    p_fila_id: filaId,
    p_resultado: resultado,
    p_pontuacao: pontuacao,
  });
  finish(eventoId, categoriaId, error, "resultado");
}

export async function registrarRetorno(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const filaId = String(formData.get("fila_id") ?? "");

  if (!uuidPattern.test(filaId)) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { error } = await supabase.rpc("pista_registrar_retorno", {
    p_fila_id: filaId,
  });
  finish(eventoId, categoriaId, error, "retorno");
}

export async function registrarRaboDaGata(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const filaId = String(formData.get("fila_id") ?? "");

  if (!uuidPattern.test(filaId)) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { error } = await supabase.rpc("pista_registrar_rabo_da_gata", {
    p_fila_id: filaId,
  });
  finish(eventoId, categoriaId, error, "rabo-da-gata");
}

export async function liberarRetorno(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const ocorrenciaId = String(formData.get("ocorrencia_id") ?? "");
  const destino = String(formData.get("destino") ?? "");

  if (
    !uuidPattern.test(ocorrenciaId) ||
    !["rodizio_atual", "proximo_rodizio"].includes(destino)
  ) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }

  const supabase = await authorize(eventoId, categoriaId, ["organizador", "locutor"]);
  const { error } = await supabase.rpc("pista_liberar_retorno", {
    p_ocorrencia_id: ocorrenciaId,
    p_destino: destino,
  });
  finish(eventoId, categoriaId, error, "retorno-liberado");
}

export async function configurarSubstituicao(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const permiteSubstituicao = formData.get("permite_substituicao") === "on";

  const supabase = await authorize(eventoId, categoriaId, ["organizador"]);
  const { error } = await supabase.rpc("pista_configurar_evento", {
    p_evento_id: eventoId,
    p_permite_substituicao: permiteSubstituicao,
  });
  finish(eventoId, categoriaId, error, "configuracao");
}

export async function solicitarBoiTvApresentacao(formData: FormData) {
  const { eventoId, categoriaId } = readScope(formData);
  const corridaId = String(formData.get("corrida_id") ?? "");
  const tipo = String(formData.get("tipo_solicitacao") ?? "");
  const reclamanteId = String(formData.get("reclamante_dupla_id") ?? "");
  if (!uuidPattern.test(corridaId) || !uuidPattern.test(reclamanteId) || !["a_favor", "contra_terceiro"].includes(tipo)) {
    redirect(`${route(eventoId, categoriaId)}&erro=campos`);
  }
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) redirect("/");
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_solicitar_com_origem", {
    p_corrida_id: corridaId,
    p_tipo: tipo,
    p_reclamante_dupla_id: reclamanteId,
    p_origem: "apresentacao",
  });
  if (error || typeof data !== "string" || !uuidPattern.test(data)) {
    redirect(`${route(eventoId, categoriaId)}&erro=boi-tv`);
  }
  revalidatePath(route(eventoId, categoriaId));
  revalidatePath(`/eventos/${eventoId}/pista-ops`);
  revalidatePath(`/painel/operacoes/${eventoId}`);
  redirect(`${route(eventoId, categoriaId)}&sucesso=boi-tv`);
}
