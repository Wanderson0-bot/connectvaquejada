"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Scope = { eventId: string; categoryId: string };
type DbError = { code?: string; message: string } | null;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readScope(formData: FormData): Scope {
  const eventId = String(formData.get("evento_id") ?? "");
  const categoryId = String(formData.get("categoria_id") ?? "");
  if (!uuidPattern.test(eventId) || !uuidPattern.test(categoryId)) redirect("/painel");
  return { eventId, categoryId };
}

function pageUrl(scope: Scope, status?: { error?: string; success?: string }) {
  const query = new URLSearchParams({ categoria: scope.categoryId });
  if (status?.error) query.set("erro", status.error);
  if (status?.success) query.set("sucesso", status.success);
  return `/eventos/${encodeURIComponent(scope.eventId)}/pista-ops?${query}`;
}

function errorKey(error: DbError): string {
  if (!error) return "operacao";
  if (error.code === "42501" || error.message.includes("PISTA_AUTH") || error.message.includes("PISTA_PROFILE") || error.message.includes("PISTA_EVENT_ROLE")) return "acesso";
  if (error.message.includes("PISTA_SUDDEN_DEATH")) return "morte-subita";
  if (error.message.includes("PISTA_SCORE_REQUIRED")) return "pontuacao";
  if (error.message.includes("PISTA_RETURN_NOT_PENDING")) return "retorno";
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
    if (error) console.error("Falha na RPC da Locução:", error.code, error.message);
    redirect(pageUrl(scope, { error: errorKey(error) }));
  }
  revalidatePath(`/eventos/${scope.eventId}/pista-ops`);
  revalidatePath(`/painel/operacoes/${scope.eventId}`);
  redirect(pageUrl(scope, { success }));
}

function validId(value: string) {
  return uuidPattern.test(value);
}

async function advanceAutomatically(supabase: Awaited<ReturnType<typeof createClient>>, roundId: string) {
  const { data, error } = await supabase.rpc("pista_ops_chamar_proxima_automatica", {
    p_rodizio_id: roundId,
    p_request_id: randomUUID(),
  });
  if (error) return { error, status: null };
  if (!data || typeof data !== "object" || !("status" in data) || typeof data.status !== "string") {
    return { error: null, status: null };
  }
  return { error: null, status: data.status };
}

function automaticAdvanceSuccess(action: "resultado" | "retorno" | "rabo-concluido", status: string | null) {
  if (!status) return `${action}-avanco-falhou`;
  if (status === "chamada") return `${action}-avanco`;
  if (status === "pausada") return `${action}-pausado`;
  if (status === "fila_concluida") return `${action}-fila-concluida`;
  if (status === "aguardando_proximo_rodizio") return `${action}-aguardando`;
  if (status === "ja_chamada") return `${action}-ja-chamada`;
  if (status === "rodizio_inativo") return `${action}-rodizio-inativo`;
  return `${action}-avanco-falhou`;
}

export async function chamarProxima(formData: FormData) {
  const scope = readScope(formData);
  const roundId = String(formData.get("rodizio_id") ?? "");
  const requestId = String(formData.get("request_id") ?? "");
  if (!validId(roundId) || !validId(requestId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_chamar_proxima", {
    p_rodizio_id: roundId,
    p_request_id: requestId,
  });
  if (error || !data || typeof data !== "object" || !("status" in data)) finish(scope, error, "", false);
  const status = (data as { status: string }).status;
  finish(scope, null, status === "aguardando_proximo_rodizio" ? "aguardando" : status === "fila_concluida" ? "fila-concluida" : "chamada");
}

export async function registrarResultado(formData: FormData) {
  const scope = readScope(formData);
  const queueItemId = String(formData.get("item_fila_id") ?? "");
  const roundId = String(formData.get("rodizio_id") ?? "");
  const result = String(formData.get("resultado") ?? "");
  const rawScore = String(formData.get("pontuacao") ?? "").trim();
  const score = Number(rawScore);
  if (result === "valeu_boi" && Number.isFinite(score) && score > 40) {
    redirect(pageUrl(scope, { error: "pontuacao-max" }));
  }
  if (!validId(queueItemId) || !validId(roundId) || !["zero", "valeu_boi"].includes(result) || !rawScore || !Number.isFinite(score) || score < 0 || (result === "zero" && score !== 0)) {
    finish(scope, null, "", false);
  }
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_registrar_resultado", {
    p_item_fila_id: queueItemId,
    p_resultado: result,
    p_pontuacao: score,
  });
  if (error || typeof data !== "string" || !validId(data)) finish(scope, error, "", false);
  const next = await advanceAutomatically(supabase, roundId);
  if (next.error) console.error("Resultado registrado, mas a chamada automática falhou:", next.error.code, next.error.message);
  else if (!next.status) console.error("Resultado registrado, mas a chamada automática retornou uma resposta inválida.");
  finish(scope, null, automaticAdvanceSuccess("resultado", next.status));
}

export async function solicitarBoiTvLocucao(formData: FormData) {
  const scope = readScope(formData);
  const runId = String(formData.get("corrida_id") ?? "");
  const type = String(formData.get("tipo_solicitacao") ?? "");
  const claimantId = String(formData.get("reclamante_dupla_id") ?? "");
  if (!validId(runId) || !validId(claimantId) || !["a_favor", "contra_terceiro"].includes(type)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_boi_tv_solicitar_com_origem", {
    p_corrida_id: runId,
    p_tipo: type,
    p_reclamante_dupla_id: claimantId,
    p_origem: "locucao",
  });
  finish(scope, error, "boi-tv-solicitado", typeof data === "string" && validId(data));
}

export async function registrarRetorno(formData: FormData) {
  const scope = readScope(formData);
  const queueItemId = String(formData.get("item_fila_id") ?? "");
  const roundId = String(formData.get("rodizio_id") ?? "");
  if (!validId(queueItemId) || !validId(roundId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_registrar_retorno", { p_item_fila_id: queueItemId });
  if (error || !data) finish(scope, error, "", false);
  const next = await advanceAutomatically(supabase, roundId);
  if (next.error) console.error("Retorno registrado, mas a chamada automática falhou:", next.error.code, next.error.message);
  else if (!next.status) console.error("Retorno registrado, mas a chamada automática retornou uma resposta inválida.");
  finish(scope, null, automaticAdvanceSuccess("retorno", next.status));
}

export async function registrarRaboDaGata(formData: FormData) {
  const scope = readScope(formData);
  const roundId = String(formData.get("rodizio_id") ?? "");
  const duoId = String(formData.get("dupla_id") ?? "");
  if (!validId(roundId) || !validId(duoId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_rabo_da_gata", {
    p_rodizio_id: roundId,
    p_dupla_id: duoId,
  });
  finish(scope, error, "rabo-encaminhado", Boolean(data));
}

export async function finalizarRaboDaGata(formData: FormData) {
  const scope = readScope(formData);
  const queueItemId = String(formData.get("item_fila_id") ?? "");
  const roundId = String(formData.get("rodizio_id") ?? "");
  if (!validId(queueItemId) || !validId(roundId)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const { data, error } = await supabase.rpc("pista_ops_finalizar_rabo_da_gata", { p_item_fila_id: queueItemId });
  if (error || typeof data !== "string" || !validId(data)) finish(scope, error, "", false);
  const next = await advanceAutomatically(supabase, roundId);
  if (next.error) console.error("Rabo da Gata concluído, mas a chamada automática falhou:", next.error.code, next.error.message);
  else if (!next.status) console.error("Rabo da Gata concluído, mas a chamada automática retornou uma resposta inválida.");
  finish(scope, null, automaticAdvanceSuccess("rabo-concluido", next.status));
}

export async function configurarChamadaAutomatica(formData: FormData) {
  const scope = readScope(formData);
  const roundId = String(formData.get("rodizio_id") ?? "");
  const rawPaused = String(formData.get("pausada") ?? "");
  if (!validId(roundId) || !["true", "false"].includes(rawPaused)) finish(scope, null, "", false);
  const supabase = await requireUser();
  const paused = rawPaused === "true";
  const { data, error } = await supabase.rpc("pista_ops_configurar_chamada_automatica", {
    p_rodizio_id: roundId,
    p_pausada: paused,
  });
  if (error || data !== paused) finish(scope, error, "", false);
  if (paused) finish(scope, null, "avanco-pausado");

  const next = await advanceAutomatically(supabase, roundId);
  if (next.error) console.error("Avanço retomado, mas a chamada automática falhou:", next.error.code, next.error.message);
  else if (!next.status) console.error("Avanço retomado, mas a chamada automática retornou uma resposta inválida.");
  finish(scope, null, next.error || !next.status ? "avanco-retomado-falhou" : "avanco-retomado");
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
