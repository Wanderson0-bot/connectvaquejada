import Image from "next/image";
import Link from "next/link";
import { randomUUID } from "node:crypto";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import styles from "./pista-ops.module.css";
import { ClassificacaoDrawer, type ClassificacaoItem } from "./ClassificacaoDrawer";
import {
  chamarProxima,
  configurarMorteSubita,
  configurarChamadaAutomatica,
  finalizarRaboDaGata,
  registrarRaboDaGata,
  registrarResultado,
  registrarRetorno,
  solicitarBoiTvLocucao,
} from "./actions";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ categoria?: string | string[]; erro?: string; sucesso?: string }>;
};

type Category = { id: string; nome: string; ordem: number };
type QueueItem = {
  id: string;
  dupla_id: string;
  numero_senha: number;
  tipo: "regular" | "rabo_da_gata";
  estado: string;
  numero_corrida: number | null;
};
type Round = {
  id: string;
  numero: number;
  quantidade_bois: number;
  estado: string;
  fila: QueueItem[];
  corridas: Run[];
  posicoes: { numero: number; estado: string; item_id: string | null }[];
};
type Run = { id: string; dupla_id: string; numero_senha: number; numero_corrida: number; estado: string; pontuacao: number | null };
type CurrentCallDetails = { vaqueiro: string | null; cavalo: string | null; equipe: string | null };
type State = {
  evento: { id: string; nome: string };
  categorias: Category[];
  minhas_funcoes: string[];
  duplas: { id: string; numero_senha: number }[];
  rodizios: Round[];
};
type BoiTvState = { habilitado: boolean; revisoes: { corrida_id: string; estado: string }[] };

const errorMessages: Record<string, string> = {
  acesso: "Seu usuário não tem uma função ativa para operar a Pista neste evento.",
  pontuacao: "Valeu Boi exige uma pontuação válida informada pelo juiz.",
  "pontuacao-max": "A pontuação de cada corrida deve ser de no máximo 40 pontos.",
  retorno: "Este retorno não está pendente ou a chamada já mudou de estado.",
  estado: "A operação não é válida para o estado atual. Atualize a tela e tente novamente.",
  "morte-subita": "Não foi possível atualizar a configuração de morte súbita.",
  operacao: "A operação falhou. Nenhuma confirmação de sucesso foi registrada.",
};

const successMessages: Record<string, string> = {
  chamada: "Próxima senha chamada.",
  aguardando: "A fila aguarda o próximo rodízio planejado.",
  "fila-concluida": "A fila do rodízio foi concluída.",
  "resultado-avanco": "Resultado registrado. A próxima senha foi chamada automaticamente.",
  "resultado-pausado": "Resultado registrado. O avanço automático está pausado.",
  "resultado-fila-concluida": "Resultado registrado. A fila do rodízio foi concluída.",
  "resultado-aguardando": "Resultado registrado. A fila aguarda o próximo rodízio planejado.",
  "resultado-ja-chamada": "Resultado registrado. Já existe uma senha chamada.",
  "resultado-rodizio-inativo": "Resultado registrado. O rodízio não está ativo, então a fila não avançou.",
  "resultado-avanco-falhou": "Resultado registrado, mas não foi possível chamar a próxima senha. Atualize a locução e tente retomar o avanço automático.",
  "retorno-avanco": "Retorno registrado. A próxima senha foi chamada automaticamente.",
  "retorno-pausado": "Retorno registrado. O avanço automático está pausado.",
  "retorno-fila-concluida": "Retorno registrado. A fila do rodízio foi concluída.",
  "retorno-aguardando": "Retorno registrado. A fila aguarda o próximo rodízio planejado.",
  "retorno-ja-chamada": "Retorno registrado. Já existe uma senha chamada.",
  "retorno-rodizio-inativo": "Retorno registrado. O rodízio não está ativo, então a fila não avançou.",
  "retorno-avanco-falhou": "Retorno registrado, mas não foi possível chamar a próxima senha. Atualize a locução e tente retomar o avanço automático.",
  "rabo-encaminhado": "Rabo da Gata encaminhado ao fim da fila.",
  "rabo-concluido-avanco": "Rabo da Gata concluído. A próxima senha foi chamada automaticamente.",
  "rabo-concluido-pausado": "Rabo da Gata concluído. O avanço automático está pausado.",
  "rabo-concluido-fila-concluida": "Rabo da Gata concluído. A fila do rodízio foi concluída.",
  "rabo-concluido-aguardando": "Rabo da Gata concluído. A fila aguarda o próximo rodízio planejado.",
  "rabo-concluido-ja-chamada": "Rabo da Gata concluído. Já existe uma senha chamada.",
  "rabo-concluido-rodizio-inativo": "Rabo da Gata concluído. O rodízio não está ativo, então a fila não avançou.",
  "rabo-concluido-avanco-falhou": "Rabo da Gata concluído, mas não foi possível chamar a próxima senha. Atualize a locução e tente retomar o avanço automático.",
  "avanco-pausado": "Avanço automático pausado.",
  "avanco-retomado": "Avanço automático retomado.",
  "avanco-retomado-falhou": "Avanço automático retomado, mas não foi possível chamar a próxima senha. Atualize a locução e tente novamente.",
  "morte-subita": "Configuração de morte súbita atualizada.",
};

function HiddenScope({ eventId, categoryId }: { eventId: string; categoryId: string }) {
  return (
    <>
      <input type="hidden" name="evento_id" value={eventId} />
      <input type="hidden" name="categoria_id" value={categoryId} />
    </>
  );
}

export default async function PistaOpsPage({ params, searchParams }: Props) {
  const { id: eventId } = await params;
  const query = await searchParams;
  const categoryId = Array.isArray(query.categoria) ? query.categoria[0] : query.categoria;
  const supabase = await createClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) redirect("/");

  const { data: eventoStatus, error: eventoStatusError } = await supabase
    .from("eventos")
    .select("status_operacional,formato_competicao")
    .eq("id", eventId)
    .maybeSingle();
  if (eventoStatusError) {
    return (
      <main className={`${styles.shell} mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-8`}>
        <p role="alert" className="rounded-lg border-l-4 border-amber-700 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          Não foi possível carregar o formato da competição. Verifique se a migration de Tropa de Elite foi aplicada.
        </p>
      </main>
    );
  }
  if (!eventoStatus) notFound();
  if (eventoStatus.formato_competicao === "tropa_de_elite") {
    return (
      <main className={`${styles.shell} mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-8`}>
        <Link href={`/eventos/${eventId}`} className="text-sm text-gray-600 underline">Voltar ao evento</Link>
        <section className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 p-5">
          <h1 className="text-2xl font-bold text-emerald-950">Tropa de Elite · fase eliminatória</h1>
          <p className="mt-2 text-emerald-950">Este formato não utiliza rodízios classificatórios. Abra o chaveamento para registrar cada boi e avançar os vencedores.</p>
          <Link href={`/eventos/${eventId}/x1`} className="mt-4 inline-flex rounded-lg bg-emerald-800 px-5 py-3 font-bold text-white">Abrir chave eliminatória</Link>
        </section>
      </main>
    );
  }

  if (eventoStatus.status_operacional !== "em_andamento") {
    const message = eventoStatus.status_operacional === "pausado"
      ? "A vaquejada está pausada. A locução ficará bloqueada até o evento ser retomado."
      : eventoStatus.status_operacional === "concluido"
        ? "A vaquejada foi concluída. A locução está encerrada."
        : eventoStatus.status_operacional === "cancelado"
          ? "A vaquejada foi anulada. A locução está encerrada."
          : "A locução ficará disponível quando a vaquejada for iniciada.";
    return (
      <main className={`${styles.shell} mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-8`}>
        <Link href="/painel" className="text-sm text-gray-600 underline">Voltar ao painel</Link>
        <p role="status" className="mt-5 rounded-lg border-l-4 border-orange-500 bg-orange-50 p-4 text-orange-950">{message}</p>
      </main>
    );
  }

  const { data, error: stateError } = await supabase.rpc("pista_ops_state", {
    p_evento_id: eventId,
    p_categoria_id: categoryId || null,
  });
  const state = data as unknown as State | null;
  const { data: deviceContext } = await supabase.rpc("pista_ops_device_context", { p_evento_id: eventId });
  const category = state?.categorias.find((item) => item.id === categoryId);
  const roles = new Set(deviceContext?.funcao ? [String(deviceContext.funcao)] : (state?.minhas_funcoes ?? []));
  const canOperate = ["organizador", "escritorio", "locutor"].some((role) => roles.has(role));
  const canJudge = roles.has("organizador") || roles.has("locutor");
  const callRequestId = randomUUID();
  const activeRound = state?.rodizios.find((round) => round.estado === "ativo");
  const currentCall = activeRound?.fila.find((item) => item.estado === "chamada");
  const { data: currentCallDetailsData } = currentCall
    ? await supabase.rpc("pista_ops_queue_item_details", { p_item_fila_id: currentCall.id })
    : { data: null };
  const currentCallDetails = (currentCallDetailsData ?? null) as unknown as CurrentCallDetails | null;
  const { data: boiTvData } = category
    ? await supabase.rpc("pista_ops_boi_tv_estado", { p_evento_id: eventId, p_categoria_id: category.id })
    : { data: null };
  const boiTvState = boiTvData as BoiTvState | null;
  const hasStartedQueue = activeRound?.fila.some((item) => item.estado !== "na_fila") ?? false;
  const currentPosition = activeRound?.posicoes.find((position) => position.item_id === currentCall?.id);
  const { data: automaticCallPaused, error: automaticCallError } = activeRound && canJudge
    ? await supabase.rpc("pista_ops_chamada_automatica_status", { p_rodizio_id: activeRound.id })
    : { data: false, error: null };
  const isAutomaticCallPaused = automaticCallPaused === true;
  const classificationRound = activeRound ?? state?.rodizios[0];
  const { data: morteSubitaAtiva, error: morteSubitaError } = category
    ? await supabase.rpc("pista_ops_morte_subita_status", { p_evento_id: eventId })
    : { data: false, error: null };
  const [partialResult, generalResult] = category && classificationRound
    ? await Promise.all([
        supabase.rpc("pista_ops_classificacao", {
          p_evento_id: eventId,
          p_categoria_id: category.id,
          p_rodizio_id: classificationRound.id,
          p_escopo: "parcial",
        }),
        supabase.rpc("pista_ops_classificacao", {
          p_evento_id: eventId,
          p_categoria_id: category.id,
          p_rodizio_id: classificationRound.id,
          p_escopo: "geral",
        }),
      ])
    : [{ data: [], error: null }, { data: [], error: null }];
  const classificationError = Boolean(partialResult.error || generalResult.error);
  const partial = (partialResult.data ?? []) as ClassificacaoItem[];
  const general = (generalResult.data ?? []) as ClassificacaoItem[];
  const errorMessage = query.erro ? errorMessages[query.erro] ?? "A operação falhou. Nenhuma confirmação de sucesso foi registrada." : null;
  const successMessage = query.sucesso ? successMessages[query.sucesso] : null;

  return (
    <main className={`${styles.shell} mx-auto min-h-screen w-full max-w-6xl px-4 py-5 sm:px-8 sm:py-7`}>
      {!stateError && state && !categoryId && (
        <section className="mx-auto max-w-3xl py-8">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm text-stone-600">{state.evento.nome}</p>
              <h1 className="text-2xl font-bold text-stone-950">Selecione uma categoria</h1>
            </div>
            <Link href="/painel" className="text-sm font-semibold text-orange-800 underline">Painel</Link>
          </div>
          {state.categorias.length === 0 ? (
            <p className="mt-5 rounded-lg bg-white p-4 text-sm text-stone-600">Este evento ainda não possui categorias.</p>
          ) : (
            <ul className="mt-5 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-white">
              {state.categorias.map((item) => (
                <li key={item.id}>
                  <Link className="flex min-h-14 items-center justify-between gap-4 px-4 py-3 font-semibold hover:bg-orange-50" href={`/eventos/${eventId}/pista-ops?categoria=${item.id}`}>
                    <span>{item.nome}</span><span className="text-sm text-orange-800">Abrir locução</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {stateError && (
        <p role="alert" className="mt-5 rounded-lg border-l-4 border-amber-700 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          Não foi possível carregar a locução. Verifique se as migrations operacionais foram aplicadas e se o usuário tem acesso ao evento.
        </p>
      )}
      {!stateError && state && categoryId && !category && (
        <p role="alert" className="mt-6 text-sm text-red-800">A categoria não pertence a este evento ou não está disponível.</p>
      )}

      {!stateError && state && categoryId && category && (
        <>
          {!canOperate && <p role="alert" className="mb-4 rounded-md bg-amber-50 p-4 text-sm text-amber-950">Seu usuário não tem uma função ativa da Pista neste evento.</p>}
          {canOperate && (
            <>
              <div className="mb-3 flex justify-end">
                <Link
                  href={`/eventos/${eventId}/pista-ops?categoria=${categoryId}`}
                  className="text-sm font-semibold text-stone-600 underline underline-offset-4 hover:text-orange-800"
                >
                  Atualizar locução
                </Link>
              </div>
              {errorMessage && <p role="alert" className="mb-4 border-l-4 border-red-700 bg-red-50 px-4 py-3 text-sm text-red-900">{errorMessage}</p>}
              {successMessage && <p role="status" className="mb-4 border-l-4 border-emerald-700 bg-emerald-50 px-4 py-3 text-sm text-emerald-950">{successMessage}</p>}
              {morteSubitaError && <p role="alert" className="mb-4 border-l-4 border-amber-700 bg-amber-50 px-4 py-3 text-sm text-amber-950">Não foi possível carregar a configuração de morte súbita.</p>}
              {automaticCallError && <p role="alert" className="mb-4 border-l-4 border-amber-700 bg-amber-50 px-4 py-3 text-sm text-amber-950">Não foi possível carregar o estado do avanço automático.</p>}

              <section className={styles.announcer} aria-label="Painel de locução">
                <header className={styles.announcerHeader}>
                  <div className={styles.brand}>
                    <Image src="/logo-connect-vaquejada.png" alt="Connect Vaquejada" width={180} height={120} className="h-20 w-48 object-contain sm:h-24 sm:w-56" />
                  </div>
                  <div className={styles.eventHeader}>
                    <div className={styles.eventInfo}>
                      <h1 className={styles.announcerEyebrow}>Painel de locução</h1>
                      <p>{state.evento.nome}</p>
                      <span>{category.nome}</span>
                    </div>
                    <div
                      className={styles.headerActions}
                      style={canJudge && !morteSubitaError
                        ? { display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", justifySelf: "center", width: "min(100%, 25rem)", gap: "10px" }
                        : undefined}
                    >
                      <div className={styles.classificationControl}>
                        <ClassificacaoDrawer
                          categoria={category.nome}
                          rodizio={classificationRound ? `Rodízio #${classificationRound.numero}` : "Sem rodízio"}
                          parcial={partial}
                          geral={general}
                          erro={classificationError}
                        />
                      </div>
                      {canJudge && !morteSubitaError && (
                        <form action={configurarMorteSubita}>
                          <HiddenScope eventId={eventId} categoryId={categoryId} />
                          <input type="hidden" name="morte_subita" value={morteSubitaAtiva ? "false" : "true"} />
                          <button
                            aria-pressed={Boolean(morteSubitaAtiva)}
                            className={`inline-flex min-h-10 w-full min-w-0 items-center justify-center gap-2 rounded-lg border px-2 py-2 text-center text-sm font-bold leading-tight shadow-md transition hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 ${morteSubitaAtiva
                              ? "border-red-700 bg-red-700 text-white hover:bg-red-800 focus-visible:outline-red-700"
                              : "border-emerald-800 bg-emerald-800 text-white hover:bg-emerald-900 focus-visible:outline-emerald-700"}`}
                          >
                            <span
                              aria-hidden="true"
                              className={`size-2.5 rounded-full ${morteSubitaAtiva ? "bg-red-200" : "bg-emerald-200"}`}
                            />
                            {morteSubitaAtiva ? "Desativar morte súbita" : "Ativar morte súbita"}
                          </button>
                        </form>
                      )}
                    </div>
                  </div>
                </header>

                <div className={styles.announcerMain}>
                  <div className={styles.announcerFacts}>
                    <div className={styles.announcerFact}>
                      <p>Categoria</p>
                      <strong>{category.nome}</strong>
                    </div>
                    <div className={styles.announcerFact}>
                      <p>Boi</p>
                      <strong>{currentPosition ? currentPosition.numero : "—"}</strong>
                    </div>
                    <div className={styles.announcerFact}>
                      <p>Rodízio</p>
                      <strong>{activeRound ? `#${activeRound.numero}` : "Aguardando"}</strong>
                    </div>
                  </div>

                  <div className={styles.currentNumber}>
                    <span>Senha atual</span>
                    <strong>{currentCall ? String(currentCall.numero_senha).padStart(2, "0") : "—"}</strong>
                    {currentCall && <p className={styles.competitorName}>{currentCallDetails?.vaqueiro || "Nome do vaqueiro indisponível"}</p>}
                    {currentCallDetails?.cavalo && <p className={styles.currentCallDetail}>Cavalo: {currentCallDetails.cavalo}</p>}
                    {currentCallDetails?.equipe && <p className={styles.currentCallDetail}>Equipe: {currentCallDetails.equipe}</p>}
                    {currentCall?.tipo === "regular" && <p>Corrida {currentCall.numero_corrida ?? "—"}</p>}
                    {currentCall?.tipo === "rabo_da_gata" && <p>Rabo da Gata</p>}
                  </div>
                </div>

                {activeRound && canJudge && !automaticCallError && (
                  <div className={styles.queueControls}>
                    <p>{isAutomaticCallPaused ? "Avanço automático pausado." : "A fila avança automaticamente após cada resultado."}</p>
                    <form action={configurarChamadaAutomatica}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <input type="hidden" name="pausada" value={isAutomaticCallPaused ? "false" : "true"} />
                      <button className={`${styles.queueControlButton} ${isAutomaticCallPaused ? styles.resumeQueueButton : ""}`}>
                        {isAutomaticCallPaused ? "Retomar avanço" : "Pausar avanço"}
                      </button>
                    </form>
                  </div>
                )}

                {activeRound && currentCall?.tipo === "regular" && canJudge ? (
                  <div className={styles.announcerActions}>
                    <form action={registrarResultado} className={styles.scoreForm}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="item_fila_id" value={currentCall.id} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <input type="hidden" name="resultado" value="valeu_boi" />
                      <label className={styles.scoreLabel}>
                        Pontuação informada pelo juiz
                        <input name="pontuacao" type="number" min="0" max="40" step="0.001" required className={styles.scoreInput} />
                        <span>Máximo de 40 pontos por corrida.</span>
                      </label>
                      <button className={`${styles.actionButton} ${styles.actionValued}`}>Valeu o Boi</button>
                    </form>
                    <form action={registrarResultado} className={styles.actionForm}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="item_fila_id" value={currentCall.id} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <input type="hidden" name="resultado" value="zero" />
                      <input type="hidden" name="pontuacao" value="0" />
                      <button className={`${styles.actionButton} ${styles.actionZero}`}>Zero</button>
                    </form>
                    <form action={registrarRetorno} className={styles.actionForm}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="item_fila_id" value={currentCall.id} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <button className={`${styles.actionButton} ${styles.actionReturn}`}>Retorno</button>
                    </form>
                    <form action={registrarRaboDaGata} className={styles.actionForm}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <input type="hidden" name="dupla_id" value={currentCall.dupla_id} />
                      <button className={`${styles.actionButton} ${styles.actionTail}`}>Rabo da Gata</button>
                    </form>
                  </div>
                ) : activeRound && currentCall?.tipo === "rabo_da_gata" && canJudge ? (
                  <div className={styles.announcerActions}>
                    <form action={finalizarRaboDaGata} className={styles.singleAction}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="item_fila_id" value={currentCall.id} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <button className={`${styles.actionButton} ${styles.actionReturn}`}>Concluir Rabo da Gata</button>
                    </form>
                  </div>
                ) : currentCall ? (
                  <p className={styles.announcerNotice}>A senha está chamada. O registro do resultado é restrito ao organizador ou locutor.</p>
                ) : activeRound && canOperate && !hasStartedQueue ? (
                  <div className={styles.callNext}>
                    <p>Chame manualmente a primeira senha do rodízio.</p>
                    <form action={chamarProxima}>
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="rodizio_id" value={activeRound.id} />
                      <input type="hidden" name="request_id" value={callRequestId} />
                      <button className={styles.callNextButton}>Chamar primeira senha</button>
                    </form>
                  </div>
                ) : activeRound && canOperate ? (
                  <p className={styles.announcerNotice}>
                    {isAutomaticCallPaused
                      ? "O avanço está pausado. Retome para chamar a próxima senha."
                      : "Aguardando o avanço automático da fila."}
                  </p>
                ) : (
                  <p className={styles.announcerNotice}>
                    Aguardando planejamento e início do rodízio no painel administrativo.
                  </p>
                )}
                {activeRound && boiTvState?.habilitado && (roles.has("organizador") || roles.has("escritorio") || roles.has("locutor")) && (
                  <section className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-stone-900">
                    <h2 className="font-bold">Boi TV · solicitações da locução</h2>
                    <p className="mt-1 text-sm">Pedidos ficam vinculados à corrida original e não pausam o avanço da fila.</p>
                    <ul className="mt-3 divide-y divide-amber-200">
                      {activeRound.corridas.filter((run) => ["zero", "valeu_boi"].includes(run.estado) && !boiTvState.revisoes.some((review) => review.corrida_id === run.id)).map((run) => (
                        <li key={run.id} className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
                          <span>Senha {run.numero_senha} · Corrida {run.numero_corrida} · {run.estado === "zero" ? "Zero" : `Valeu Boi · ${run.pontuacao ?? 0} pontos`}</span>
                          {run.estado === "zero" ? (
                            <form action={solicitarBoiTvLocucao} className="flex gap-2">
                              <HiddenScope eventId={eventId} categoryId={categoryId} />
                              <input type="hidden" name="corrida_id" value={run.id} />
                              <input type="hidden" name="tipo_solicitacao" value="a_favor" />
                              <input type="hidden" name="reclamante_dupla_id" value={run.dupla_id} />
                              <button className="rounded border border-amber-700 px-3 py-2 font-semibold text-amber-950">Boi a favor</button>
                            </form>
                          ) : (
                            <form action={solicitarBoiTvLocucao} className="flex flex-wrap items-center gap-2">
                              <HiddenScope eventId={eventId} categoryId={categoryId} />
                              <input type="hidden" name="corrida_id" value={run.id} />
                              <input type="hidden" name="tipo_solicitacao" value="contra_terceiro" />
                              <label>Solicitante<select name="reclamante_dupla_id" required defaultValue="" className="ml-2 h-10 rounded border px-2"><option value="" disabled>Escolher senha</option>{state.duplas.filter((dupla) => dupla.id !== run.dupla_id).map((dupla) => <option key={dupla.id} value={dupla.id}>Senha {dupla.numero_senha}</option>)}</select></label>
                              <button className="rounded border border-amber-700 px-3 py-2 font-semibold text-amber-950">Boi contra</button>
                            </form>
                          )}
                        </li>
                      ))}
                    </ul>
                  </section>
                )}
              </section>
            </>
          )}
        </>
      )}
    </main>
  );
}
