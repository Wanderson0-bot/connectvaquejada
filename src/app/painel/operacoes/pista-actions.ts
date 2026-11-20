"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Scope = { eventId: string; categoryId: string; returnToPanel: boolean };
type DbError = { code?: string; message: string } | null;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readScope(formData: FormData): Scope {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  if (!uuidPattern.test(eventId) || !uuidPattern.test(categoryId)) redirect("/painel");
  return {
    eventId,
    categoryId,
    returnToPanel: formData.get("origem") === "painel",
  };
}

function pageUrl(scope: Scope, status?: { error?: string; success?: string }) {
  const query = new URLSearchParams({ categoria: scope.categoryId });
  if (status?.error) query.set("erro", status.error);
  if (status?.success) query.set("sucesso", status.success);
  const path = scope.returnToPanel
    ? `/painel/operacoes/${encodeURIComponent(scope.eventId)}`
    : `/eventos/${encodeURIComponent(scope.eventId)}/pista-ops`;
  return `${path}?${query}`;
}

function errorKey(error: DbError): string {
  if (!error) return "operacao";
  if (error.code === "23505" && error.message.includes("pista_ops_one_active_round_per_event_uq")) return "rodizio-evento-ativo";
  if (error.code === "42501" || error.message.includes("PISTA_AUTH") || error.message.includes("PISTA_PROFILE") || error.message.includes("PISTA_EVENT_ROLE")) return "acesso";
  if (error.message.includes("PISTA_SCORE_REQUIRED")) return "pontuacao";
  if (error.message.includes("PISTA_RETURN_NOT_PENDING")) return "retorno";
  if (error.message.includes("PISTA_SECOND_RUN_ALREADY_USED")) return "corrida-ja-utilizada";
  if (error.message.includes("PISTA_STARTED_ROUND_POLICY_PENDING")) return "rodizio-iniciado";
  if (error.message.includes("PISTA_INVALID_BULL_COUNT") || error.message.includes("PISTA_INVALID_PRIZE") || error.message.includes("PISTA_TIE_TERMS")) return "campos";
  if (error.message.includes("PISTA_SUBSTITUTION_DISABLED")) return "substituicao-desativada";
  if (error.message.includes("PISTA_TV_DISABLED")) return "boi-tv-desativado";
  if (error.message.includes("PISTA_TV_REVIEW_PENDING")) return "boi-tv-pendente";
  if (error.message.includes("PISTA_TV")) return "boi-tv-estado";
  if (error.message.includes("PISTA_ROUND_ORDER_REQUIRED")) return "ordem-rodizio";
  if (error.message.includes("PISTA_CATEGORY") || error.message.includes("PISTA_ENTRY_NOT_ELIGIBLE")) return "inscricao";
  if (error.message.includes("PISTA_ROUND") || error.message.includes("PISTA_RUN") || error.message.includes("PISTA_POSITION") || error.message.includes("PISTA_QUEUE") || error.message.includes("PISTA_RESULT")) return "estado";
  return "operacao";
}

async function requireUser() {
  const supabase = await createClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) redirect("/");
  return supabase;
}

function finish(scope: Scope, error: DbError, success: string, hasData = true): never {
  if (error || !hasData) {
    if (error) console.error("Falha na RPC operacional da Pista:", error.code, error.message);
    redirect(pageUrl(scope, { error: errorKey(error) }));
  }
  revalidatePath(`/eventos/${scope.eventId}/pista-ops`);
  revalidatePath(`/painel/operacoes/${scope.eventId}`);
  revalidatePath(`/eventos/${scope.eventId}`);
  redirect(pageUrl(scope, { success }));
}

function validId(value: string) {
  return uuidPattern.test(value);
}

export async function planejarRodizio(formData: FormData) {
  const scope = readScope(formData);
  const bulls = Number(formData.get("quantidade_bois"));
  if (!Number.isSafeInteger(bulls) || bulls < 1) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_planejar_rodizio", {
    p_evento_id: scope.eventId,
    p_categoria_id: scope.categoryId,
    p_quantidade_bois: bulls,
  });
  finish(scope, error, "planejado", typeof data === "string" && validId(data));
}

export async function iniciarRodizio(formData: FormData) {
  const scope = readScope(formData);
  const roundId = String(formData.get("rodizio_id") ?? "");
  if (!validId(roundId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_iniciar_rodizio", { p_rodizio_id: roundId });
  finish(scope, error, "iniciado", Boolean(data));
}

export async function configurarMorteSubita(formData: FormData) {
  const scope = readScope(formData);
  const rawValue = String(formData.get("morte_subita") ?? "");
  if (!["true", "false"].includes(rawValue)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_configurar_morte_subita", {
    p_evento_id: scope.eventId,
    p_ativada: rawValue === "true",
  });
  finish(scope, error, "morte-subita", data === (rawValue === "true"));
}

export async function configurarBoiTv(formData: FormData) {
  const scope = readScope(formData);
  const raw = String(formData.get("boi_tv") ?? "");
  if (!['true','false'].includes(raw)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_configurar", {
    p_evento_id: scope.eventId, p_habilitado: raw === "true",
  });
  finish(scope, error, "boi-tv-configurado", data === (raw === "true"));
}

export async function decidirBoiTv(formData: FormData) {
  const scope = readScope(formData);
  const reviewId = String(formData.get("revisao_id") ?? "");
  const result = String(formData.get("resultado") ?? "");
  const rawScore = String(formData.get("pontuacao") ?? "0").trim();
  const score = Number(rawScore);
  const justification = String(formData.get("justificativa") ?? "").trim();
  if (!validId(reviewId) || !["zero","valeu_boi"].includes(result) || !Number.isFinite(score) || score < 0 || score > 40 || (result === "zero" && score !== 0) || justification.length < 3) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_decidir", {
    p_revisao_id: reviewId, p_resultado: result, p_pontuacao: score, p_justificativa: justification,
  });
  finish(scope, error, "boi-tv-julgado", typeof data === "string" && validId(data));
}

export async function liberarRetorno(formData: FormData) {
  const scope = readScope(formData);
  const queueItemId = String(formData.get("item_fila_id") ?? "");
  if (!validId(queueItemId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_liberar_retorno", { p_item_fila_id: queueItemId });
  if (error || !data || typeof data !== "object" || !("status" in data)) finish(scope, error, "", false);
  finish(scope, null, (data as { status: string }).status === "liberado" ? "retorno-liberado" : "aguardando");
}

export async function registrarRaboDaGata(formData: FormData) {
  const scope = readScope(formData);
  const roundId = String(formData.get("rodizio_id") ?? "");
  const entryId = String(formData.get("dupla_id") ?? "");
  if (!validId(roundId) || !validId(entryId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_rabo_da_gata", {
    p_rodizio_id: roundId,
    p_dupla_id: entryId,
  });
  if (error || !data || typeof data !== "object" || !("status" in data)) finish(scope, error, "", false);
  finish(scope, null, (data as { status: string }).status === "encaminhado" ? "rabo-encaminhado" : "aguardando");
}

export async function substituirDupla(formData: FormData) {
  const scope = readScope(formData);
  const queueItemId = String(formData.get("item_fila_id") ?? "");
  const competitorId = String(formData.get("competidor_id") ?? "");
  if (!validId(queueItemId) || !validId(competitorId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_substituir_dupla", {
    p_item_fila_id: queueItemId,
    p_competidor_id: competitorId,
  });
  finish(scope, error, "substituicao", typeof data === "string" && validId(data));
}

export async function corrigirResultado(formData: FormData) {
  const scope = readScope(formData);
  const runId = String(formData.get("corrida_id") ?? "");
  const result = String(formData.get("resultado") ?? "");
  const rawScore = String(formData.get("pontuacao") ?? "").trim();
  const score = Number(rawScore);
  const reason = String(formData.get("justificativa") ?? "").trim();
  if (!validId(runId) || !["zero", "valeu_boi"].includes(result) || !rawScore || !Number.isFinite(score) || score < 0 || (result === "valeu_boi" && score > 40) || (result === "zero" && score !== 0) || !reason) {
    finish(scope, null, "", false);
  }
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_corrigir_resultado", {
    p_corrida_id: runId,
    p_resultado: result,
    p_pontuacao: score,
    p_justificativa: reason,
  });
  finish(scope, error, "correcao", typeof data === "string" && validId(data));
}

export async function configurarSubstituicao(formData: FormData) {
  const scope = readScope(formData);
  const allow = String(formData.get("permitir_substituicao") ?? "") === "true";
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_configurar_substituicao", {
    p_evento_id: scope.eventId,
    p_permitir: allow,
  });
  finish(scope, error, "configuracao", typeof data === "boolean");
}

export async function salvarPremiacao(formData: FormData) {
  const scope = readScope(formData);
  const rawPlaces = String(formData.get("colocacoes") ?? "");
  let places: unknown;
  try {
    places = JSON.parse(rawPlaces);
  } catch {
    finish(scope, null, "", false);
  }
  if (!Array.isArray(places)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_salvar_premiacao", {
    p_evento_id: scope.eventId,
    p_categoria_id: scope.categoryId,
    p_colocacoes: places,
  });
  finish(scope, error, "premiacao", Number.isSafeInteger(data) && Number(data) > 0);
}

export async function registrarEmpate(formData: FormData) {
  const scope = readScope(formData);
  const participants = formData.getAll("participantes").map(String);
  const decision = String(formData.get("decisao") ?? "").trim();
  const terms = String(formData.get("termos") ?? "").trim();
  if (participants.length < 2 || participants.some((id) => !validId(id)) || !decision || !terms) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_registrar_empate", {
    p_evento_id: scope.eventId,
    p_categoria_id: scope.categoryId,
    p_participantes: participants,
    p_decisao: decision,
    p_termos: terms,
  });
  finish(scope, error, "empate", typeof data === "string" && validId(data));
}
