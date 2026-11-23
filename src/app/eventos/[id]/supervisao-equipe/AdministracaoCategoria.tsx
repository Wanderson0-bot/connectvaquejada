import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ConfirmForm } from "@/components/ConfirmForm";
import { CorridasPorSenha } from "./CorridasPorSenha";
import {
  configurarMorteSubita,
  iniciarRodizio,
  liberarRetorno,
  planejarRodizio,
  registrarRaboDaGata,
  configurarBoiTv,
  decidirBoiTv,
} from "@/app/painel/operacoes/pista-actions";

type QueueItem = {
  id: string;
  dupla_id: string;
  numero_senha: number;
  tipo: "regular" | "rabo_da_gata";
  estado: string;
  eh_retorno: boolean;
  corrida_id: string | null;
  numero_corrida: number | null;
};
type Run = {
  id: string;
  dupla_id: string;
  numero_senha: number;
  numero_corrida: number;
  estado: string;
  pontuacao: number | null;
  retornos_realizados: number;
};
type Round = {
  id: string;
  numero: number;
  quantidade_bois: number;
  estado: string;
  iniciado_em: string | null;
  terminado_em: string | null;
  fila: QueueItem[];
  posicoes: { numero: number; estado: string; item_id: string | null }[];
  corridas: Run[];
};
type EventActiveRound = {
  id: string;
  categoria_id: string;
  categoria_nome: string;
  numero: number;
  estado: string;
};
type State = {
  evento: { id: string; nome: string };
  categorias: { id: string; nome: string; ordem: number }[];
  minhas_funcoes: string[];
  duplas: { id: string; numero_senha: number }[];
  rodizios: Round[];
};
type BoiTvState = {
  habilitado: boolean;
  revisoes: { id: string; corrida_id: string; estado: "em_analise" | "decidido"; resultado_inicial: string; pontuacao_inicial: number; resultado_alternativa: string | null; pontuacao_alternativa: number | null; tipo_solicitacao: "a_favor" | "contra_terceiro"; reclamante_dupla_id: string; reclamante_senha: number; reclamante: string | null; senha: number; numero_corrida: number; vaqueiro: string | null; solicitada_em: string; julgada_em: string | null; justificativa: string | null }[];
};

const errorMessages: Record<string, string> = {
  acesso: "Seu usuário não tem uma função ativa para administrar esta operação.",
  campos: "Confira os dados informados e tente novamente.",
  pontuacao: "Valeu Boi exige uma pontuação válida informada pelo juiz.",
  retorno: "Este retorno não está pendente ou a chamada já mudou de estado.",
  "rodizio-iniciado": "Não é possível alterar o planejamento enquanto há rodízio ativo.",
  "rodizio-evento-ativo": "Já existe um rodízio ativo ou aguardando neste evento. Termine ou avance esse rodízio antes de iniciar outro.",
  "ordem-rodizio": "Inicie os rodízios planejados em ordem.",
  inscricao: "A inscrição não pertence a esta categoria/evento ou foi cancelada.",
  estado: "A operação não é válida para o estado atual. Atualize a tela e tente novamente.",
  operacao: "A operação falhou. Nenhuma confirmação de sucesso foi registrada.",
  "boi-tv-desativado": "Ative o boi de TV nas configurações do evento antes de encaminhar uma corrida.",
  "boi-tv-pendente": "Esta corrida já está aguardando a decisão da alternativa.",
  "boi-tv-estado": "Não foi possível abrir ou concluir esta análise do boi de TV.",
};

const successMessages: Record<string, string> = {
  planejado: "Rodízio planejado.",
  iniciado: "Rodízio iniciado.",
  aguardando: "Estado preservado: aguardando próximo rodízio planejado.",
  "fila-concluida": "Fila do rodízio concluída.",
  "retorno-liberado": "Retorno liberado e colocado na fila.",
  "rabo-encaminhado": "Rabo da Gata encaminhado sem reserva de posição.",
  "rabo-concluido": "Rabo da Gata concluído sem consumir boi.",
  "morte-subita": "Configuração de morte súbita atualizada.",
  "boi-tv-configurado": "Configuração do boi de TV atualizada para o evento.",
  "boi-tv-julgado": "Decisão da alternativa registrada e resultado final atualizado.",
};

function HiddenScope({ eventId, categoryId }: { eventId: string; categoryId: string }) {
  return (
    <>
      <input type="hidden" name="evento_id" value={eventId} />
      <input type="hidden" name="categoria_id" value={categoryId} />
      <input type="hidden" name="origem" value="painel" />
    </>
  );
}

function Section({ title, badge, children }: { title: string; badge?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="min-w-0 rounded-xl border border-stone-200 bg-white p-4 sm:p-5">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-base font-semibold text-stone-950">{title}</h3>
        {badge}
      </header>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function SubmitButton({ children }: { children: React.ReactNode }) {
  return <button className="inline-flex min-h-10 items-center justify-center rounded-md bg-emerald-900 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800">{children}</button>;
}

const statusRodizio: Record<string, string> = {
  ativo: "Em andamento",
  aguardando_proximo_rodizio: "Aguardando próximo rodízio",
  planejado: "Planejado",
  finalizado: "Finalizado",
};

function formatarHorario(value: string | null) {
  return value
    ? new Intl.DateTimeFormat("pt-BR", {
        timeZone: "America/Sao_Paulo",
        day: "2-digit",
        month: "2-digit",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(new Date(value))
    : "—";
}

export async function AdministracaoCategoria({ eventId, categoryId, erro, sucesso }: {
  eventId: string;
  categoryId: string;
  erro?: string;
  sucesso?: string;
}) {
  const supabase = await createClient();
  const { data, error: stateError } = await supabase.rpc("pista_ops_state", {
    p_evento_id: eventId,
    p_categoria_id: categoryId || null,
  });
  const { data: eventActiveRoundData, error: eventActiveRoundError } = categoryId
    ? await supabase.rpc("pista_ops_active_round_event", { p_evento_id: eventId })
    : { data: [], error: null };
  const eventActiveRound = ((eventActiveRoundData ?? []) as unknown as EventActiveRound[])[0] ?? null;
  const state = data as unknown as State | null;
  const { data: modelos, error: modelosError } = categoryId
    ? await supabase.rpc("pista_ops_categorias", { p_evento_id: eventId }).eq("id", categoryId).maybeSingle()
    : { data: null, error: null };
  const eliminatoria = (modelos as { modelo_competicao: string } | null)?.modelo_competicao === "eliminatoria";
  const category = state?.categorias.find((item) => item.id === categoryId);
  const roles = new Set(state?.minhas_funcoes ?? []);
  const canOperate = ["organizador", "escritorio", "locutor"].some((role) => roles.has(role));
  const canOrganize = roles.has("organizador");
  const canOffice = canOrganize || roles.has("escritorio");
  const canConfigureSuddenDeath = canOrganize || roles.has("locutor");

  const { data: morteSubitaAtiva, error: morteSubitaError } = category
    ? await supabase.rpc("pista_ops_morte_subita_status", { p_evento_id: eventId })
    : { data: false, error: null };
  const { data: boiTvData, error: boiTvError } = category
    ? await supabase.rpc("pista_ops_boi_tv_estado", { p_evento_id: eventId, p_categoria_id: category.id })
    : { data: null, error: null };
  const boiTvState = boiTvData as BoiTvState | null;
  const { data: roundTimesData, error: roundTimesError } = category
    ? await supabase.rpc("pista_ops_round_timestamps", { p_evento_id: eventId, p_categoria_id: category.id })
    : { data: [], error: null };
  const roundTimesById = new Map<string, { iniciado_em: string | null; terminado_em: string | null }>(
    ((roundTimesData ?? []) as { id: string; iniciado_em: string | null; terminado_em: string | null }[]).map((round) => [
      String(round.id),
      { iniciado_em: round.iniciado_em, terminado_em: round.terminado_em },
    ] as const),
  );
  const rodizios = (state?.rodizios ?? []).map((round) => ({
    ...round,
    iniciado_em: roundTimesById.get(round.id)?.iniciado_em ?? null,
    terminado_em: roundTimesById.get(round.id)?.terminado_em ?? null,
  }));
  const activeRound = rodizios.find((round) => round.estado === "ativo");
  const nextPlannedRound = rodizios
    .filter((round) => round.estado === "planejado")
    .sort((left, right) => left.numero - right.numero)[0];
  const waitingRound = rodizios.find((round) => round.estado === "aguardando_proximo_rodizio");
  const rodiziosRecentes = [...rodizios].sort((a, b) => b.numero - a.numero);
  const rodizioAtual = activeRound ?? waitingRound ?? nextPlannedRound ?? rodiziosRecentes[0];
  const podePlanejar = !activeRound && !waitingRound && !nextPlannedRound && !eventActiveRound;
  const errorMessage = erro ? errorMessages[erro] ?? "A operação falhou. Nenhum sucesso foi registrado." : null;
  const successMessage = sucesso ? successMessages[sucesso] : null;

  return (
    <section aria-labelledby="administracao-categoria" className="space-y-4">
      <header className="flex flex-wrap items-start justify-between gap-4 rounded-xl border border-stone-200 bg-white p-4 sm:p-5">
        <div>
          <h2 id="administracao-categoria" className="text-xl font-bold text-stone-950">Administrar categoria</h2>
          {category && <p className="mt-1 text-base font-semibold text-stone-700">{category.nome}</p>}
          {rodizioAtual && <p className="mt-2 inline-flex rounded-full bg-amber-50 px-3 py-1 text-sm font-semibold text-amber-900">
            Rodízio #{rodizioAtual.numero} · {statusRodizio[rodizioAtual.estado] ?? rodizioAtual.estado.replaceAll("_", " ")}
          </p>}
          {category && !rodizioAtual && !eliminatoria && <p className="mt-2 text-sm text-stone-600">Sem rodízio nesta categoria</p>}
        </div>
        <div className="flex flex-wrap gap-2">
          {category && <Link href={`/eventos/${eventId}/pista-ops?categoria=${category.id}`} className="operation-primary">{eliminatoria ? "Abrir eliminatória" : "Abrir Locução"}</Link>}
          <Link href="/painel" className="operation-secondary">Membros e funções</Link>
        </div>
      </header>

      {errorMessage && <p role="alert" className="mb-5 rounded-lg bg-red-50 p-4 text-sm text-red-900">{errorMessage}</p>}
      {successMessage && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">{successMessage}</p>}
      {stateError && <p role="alert" className="rounded-lg bg-amber-50 p-4 text-sm text-amber-950">Não foi possível carregar a operação. Confira se as migrations foram aplicadas e se o usuário tem acesso.</p>}
      {modelosError && <p role="alert" className="mb-5 rounded-lg bg-red-50 p-4 text-sm text-red-900">Não foi possível carregar os modelos das categorias.</p>}
      {eventActiveRoundError && <p role="alert" className="mb-5 rounded-lg bg-amber-50 p-4 text-sm text-amber-950">Não foi possível verificar se outra categoria já tem um rodízio ativo. Atualize as migrations operacionais.</p>}
      {(morteSubitaError || roundTimesError || boiTvError) && <p role="alert" className="rounded-lg bg-amber-50 p-4 text-sm text-amber-950">Não foi possível carregar as configurações e os horários do rodízio.</p>}

      {!stateError && state && categoryId && !category && <p role="alert" className="rounded-lg bg-red-50 p-4 text-sm text-red-900">A categoria não pertence a esta operação.</p>}
      {!stateError && state && categoryId && category && (
        <div className="space-y-4">
          {!canOperate ? (
            <p role="alert" className="border-t border-stone-200 py-5 text-sm text-amber-900">Seu usuário não tem uma função ativa da Pista neste evento.</p>
          ) : (
            <>
              {eventActiveRound && eventActiveRound.categoria_id !== categoryId && (
                <p role="status" className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
                  O rodízio #{eventActiveRound.numero} da categoria {eventActiveRound.categoria_nome} está {eventActiveRound.estado === "ativo" ? "em andamento" : "aguardando o próximo rodízio"}. Este evento permite um rodízio por vez.{" "}
                  <Link className="font-semibold underline" href={`/eventos/${eventId}/supervisao-equipe?categoria=${eventActiveRound.categoria_id}`}>Abrir essa categoria</Link>
                </p>
              )}
              <div className={`grid items-start gap-4 ${eliminatoria ? "" : "lg:grid-cols-2"}`}>
              {!eliminatoria && !modelosError && (canOffice || canConfigureSuddenDeath) && (
                <Section title="Planejamento do rodízio" badge={canConfigureSuddenDeath && !morteSubitaError && (
                  <span className={`rounded-full px-3 py-1 text-xs font-semibold ${morteSubitaAtiva ? "bg-emerald-100 text-emerald-900" : "bg-stone-100 text-stone-700"}`}>
                    Morte súbita: {morteSubitaAtiva ? "Ativada" : "Desativada"}
                  </span>
                )}>
                  {canConfigureSuddenDeath && !morteSubitaError && <div className="mb-5 rounded-lg bg-stone-50 p-3">
                    <p className="text-sm text-stone-700">
                      {morteSubitaAtiva ? "Zero na primeira corrida elimina o direito à segunda." : "Mesmo com Zero na primeira corrida, a segunda é liberada."}
                      {" "}Se houver Retorno na primeira, a segunda fica para o próximo rodízio.
                    </p>
                    <form action={configurarMorteSubita} className="mt-3">
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="morte_subita" value={morteSubitaAtiva ? "false" : "true"} />
                      <button className="operation-secondary">{morteSubitaAtiva ? "Desativar morte súbita" : "Ativar morte súbita"}</button>
                    </form>
                  </div>}
                  {canOffice && (
                    <form action={planejarRodizio}>
                      <fieldset disabled={!podePlanejar} className="grid min-w-0 items-end gap-2 disabled:opacity-60 sm:grid-cols-[minmax(0,1fr)_auto]">
                        <HiddenScope eventId={eventId} categoryId={categoryId} />
                        <label className="grid gap-1 text-sm font-medium">Quantidade de bois
                          <input name="quantidade_bois" type="number" min="1" step="1" required aria-describedby="quantidade-bois-ajuda"
                            className="h-10 w-full min-w-0 rounded-md border border-stone-300 px-3" />
                        </label>
                        <SubmitButton>Planejar rodízio</SubmitButton>
                        <p id="quantidade-bois-ajuda" className="text-xs text-stone-600 sm:col-span-2">Informe um número inteiro maior que zero.</p>
                      </fieldset>
                    </form>
                  )}
                  {canOffice && activeRound && <p className="mb-3 text-sm text-stone-600">A liberação da segunda corrida segue o modo de morte súbita acima. Retornos da primeira corrida permanecem neste rodízio.</p>}
                  {canOperate && nextPlannedRound && !activeRound && !waitingRound && !eventActiveRound && (
                    <ConfirmForm action={iniciarRodizio} message={`Iniciar o rodízio ${nextPlannedRound.numero}? A fila será montada em ordem de senha e não poderá ser reordenada depois.`} className="mt-3">
                      <HiddenScope eventId={eventId} categoryId={categoryId} />
                      <input type="hidden" name="rodizio_id" value={nextPlannedRound.id} />
                      <SubmitButton>Iniciar rodízio #{nextPlannedRound.numero}</SubmitButton>
                    </ConfirmForm>
                  )}
                  {canOffice && activeRound && <p className="mt-3 text-sm text-stone-600">Uma chamada ocupa uma única posição. O Rabo da Gata só ocupa posição após ser chamado.</p>}

                  {canOperate && waitingRound && <footer className="mt-5 border-t border-stone-200 pt-3">
                    <p role="status" className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-950">
                      Rodízio #{waitingRound.numero} aguardando próximo rodízio planejado. Nenhuma corrida foi descartada.
                    </p>
                  </footer>}
                </Section>
              )}

              {canOffice && boiTvState && (
                <Section title="Boi de TV">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <p className="rounded-full bg-amber-50 px-3 py-1 text-sm font-semibold text-amber-900">No evento: {boiTvState.habilitado ? "Disponível" : "Desativado"}</p>
                    {canOrganize && <form action={configurarBoiTv}>
                      <HiddenScope eventId={eventId} categoryId={category.id} />
                      <input type="hidden" name="boi_tv" value={boiTvState.habilitado ? "false" : "true"} />
                      <SubmitButton>{boiTvState.habilitado ? "Desativar no evento" : "Ativar no evento"}</SubmitButton>
                    </form>}
                  </div>
                  <p className="mt-3 text-sm text-stone-600">A configuração vale para todo o evento. A decisão da análise atualiza o resultado válido para a classificação.</p>
                  {boiTvState.habilitado && <div className="mt-4 flex flex-wrap gap-2">
                    {canOrganize && <Link href={`/painel/dispositivos?evento=${eventId}&funcao=boi_tv`} className="operation-secondary">Autorizar dispositivo BOI TV</Link>}
                    <Link href={`/boi-tv/${eventId}`} className="operation-secondary">Abrir central BOI TV do evento</Link>
                  </div>}
                  <a href="#historico-analises-categoria" className="mt-4 inline-flex text-sm font-semibold text-orange-900 underline">
                    Histórico da categoria · {boiTvState.revisoes.filter(({ estado }) => estado === "em_analise").length} em análise · {boiTvState.revisoes.filter(({ estado }) => estado === "decidido").length} decididas
                  </a>
                </Section>
              )}
              </div>

              <Section title="Corridas registradas">
                <CorridasPorSenha key={categoryId} rodizios={rodiziosRecentes} rodizioInicial={rodizioAtual?.id} />
              </Section>

              {activeRound && (
                <>
                  <Section title="Posições do boi">
                    <ol className="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-6">
                      {activeRound.posicoes.map((position) => {
                        const item = activeRound.fila.find((entry) => entry.id === position.item_id);
                        return (
                          <li key={position.numero} className={`min-h-16 rounded-md border p-3 ${position.estado === "ocupada" ? "border-amber-500 bg-amber-50" : position.estado === "consumida" ? "border-stone-300 bg-stone-100" : "border-emerald-300 bg-emerald-50"}`}>
                            <span className="text-xs text-stone-600">Posição {position.numero}</span>
                            <span className="mt-1 block text-sm font-semibold">{position.estado === "livre" ? "Livre" : position.estado === "consumida" ? "Consumida" : `Senha ${item?.numero_senha ?? "—"}`}</span>
                          </li>
                        );
                      })}
                    </ol>
                  </Section>

                  <Section title="Fila e chamadas">
                    {activeRound.fila.length === 0 ? <p className="text-sm text-stone-600">A fila deste rodízio está vazia.</p> : (
                      <ul className="divide-y divide-stone-200 border-y border-stone-200">
                        {activeRound.fila.filter((item) => item.estado !== "encaminhada").map((item) => (
                          <li key={item.id} className="grid gap-4 py-4 lg:grid-cols-[1fr_auto] lg:items-start">
                            <div>
                              <p className="font-semibold">Senha {item.numero_senha}{item.tipo === "regular" ? ` · Corrida ${item.numero_corrida}` : " · Rabo da Gata"}</p>
                              <p className="mt-1 text-sm text-stone-600">{item.eh_retorno ? "Retorno liberado" : item.estado === "retorno_pendente" ? "Retorno pendente de liberação" : item.estado === "aguardando_proximo" ? "Aguardando próximo rodízio" : item.estado === "chamada" ? "Chamada atual" : item.estado === "concluida" ? "Concluída" : "Na fila"}</p>
                            </div>
                            {item.estado === "retorno_pendente" && canOffice && (
                              <ConfirmForm action={liberarRetorno} message="Liberar este retorno para a fila atual? O retorno só consumirá posição quando for chamado e realizado.">
                                <HiddenScope eventId={eventId} categoryId={categoryId} />
                                <input type="hidden" name="item_fila_id" value={item.id} />
                                <SubmitButton>Liberar retorno</SubmitButton>
                              </ConfirmForm>
                            )}
                          </li>
                        ))}
                      </ul>
                    )}
                  </Section>

                  {canOffice && (
                    <Section title="Rabo da Gata">
                      <ConfirmForm action={registrarRaboDaGata} message="Encaminhar Rabo da Gata ao fim da fila disponível sem reservar posição?" className="flex flex-wrap items-end gap-3">
                        <HiddenScope eventId={eventId} categoryId={categoryId} />
                        <input type="hidden" name="rodizio_id" value={activeRound.id} />
                        <label className="grid gap-1 text-sm font-medium">Dupla
                          <select name="dupla_id" required defaultValue="" className="h-10 min-w-56 rounded-md border border-stone-300 px-3">
                            <option value="" disabled>Selecionar dupla</option>
                            {state.duplas.map((entry) => <option key={entry.id} value={entry.id}>Senha {entry.numero_senha}</option>)}
                          </select>
                        </label>
                        <SubmitButton>Encaminhar sem reservar posição</SubmitButton>
                      </ConfirmForm>
                    </Section>
                  )}
                </>
              )}

              {rodizios.length > 0 && (
                <Section title="Rodízios da categoria">
                  <ul className="divide-y divide-stone-200">
                    {rodiziosRecentes.map((round) => <li key={round.id} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 py-2 text-sm">
                      <p className="font-semibold">#{round.numero} · {round.quantidade_bois} bois · {statusRodizio[round.estado] ?? round.estado.replaceAll("_", " ")}</p>
                      <p className="mt-1 text-xs text-stone-600">Início: {formatarHorario(round.iniciado_em)}</p>
                      <p className="text-xs text-stone-600">Término: {round.terminado_em ? formatarHorario(round.terminado_em) : round.estado === "ativo" ? "Em andamento" : "—"}</p>
                    </li>)}
                  </ul>
                </Section>
              )}

              <div id="historico-analises-categoria" className="scroll-mt-4">
              {canOffice && boiTvState && (
                <Section title="Histórico de análises">
                  {boiTvState.revisoes.length ? <ul className="divide-y divide-stone-200">
                    {boiTvState.revisoes.map((review) => <li key={review.id} className="py-3">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div><p className="font-semibold">Senha {review.senha} · Corrida {review.numero_corrida}{review.vaqueiro ? ` · ${review.vaqueiro}` : ""}</p><p className="mt-1 text-sm text-stone-600">{review.tipo_solicitacao === "a_favor" ? "Boi a favor" : "Boi contra/de terceiro"} · Solicitante: Senha {review.reclamante_senha}{review.reclamante ? ` (${review.reclamante})` : ""}</p><p className="mt-1 text-sm text-stone-600">Julgamento inicial: {review.resultado_inicial === "zero" ? "Zero" : `Valeu Boi · ${review.pontuacao_inicial} pontos`} · {review.estado === "em_analise" ? "Em análise" : `Decisão: ${review.resultado_alternativa === "zero" ? "Zero" : `Valeu Boi · ${review.pontuacao_alternativa} pontos`}`}</p></div>
                        <time className="text-xs text-stone-500">Solicitado em {formatarHorario(review.solicitada_em)}</time>
                      </div>
                      {review.estado === "em_analise" && canOrganize ? <form action={decidirBoiTv} className="mt-4 flex flex-wrap items-end gap-3"><HiddenScope eventId={eventId} categoryId={category.id}/><input type="hidden" name="revisao_id" value={review.id}/><label className="grid gap-1 text-sm font-medium">Resultado da alternativa<select name="resultado" className="h-10 rounded-md border px-3"><option value="zero">Zero</option><option value="valeu_boi">Valeu Boi</option></select></label><label className="grid gap-1 text-sm font-medium">Pontos (se valer)<input name="pontuacao" type="number" min="0" max="40" step="0.001" defaultValue="0" className="h-10 w-32 rounded-md border px-3"/></label><label className="grid min-w-56 flex-1 gap-1 text-sm font-medium">Justificativa<input name="justificativa" required minLength={3} className="h-10 rounded-md border px-3"/></label><SubmitButton>Registrar decisão</SubmitButton></form> : review.justificativa && <p className="mt-2 text-sm text-stone-600">Justificativa: {review.justificativa}</p>}
                    </li>)}
                  </ul> : <p className="mt-2 text-sm text-stone-600">Nenhum boi enviado para análise nesta categoria.</p>}
                </Section>
              )}

              </div>
            </>
          )}
        </div>
      )}
    </section>
  );
}
