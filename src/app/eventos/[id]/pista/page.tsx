import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  chamarProxima,
  configurarSubstituicao,
  iniciarCorrida,
  iniciarRodizio,
  liberarRetorno,
  planejarRodizio,
  registrarRaboDaGata,
  registrarResultado,
  registrarRetorno,
  solicitarBoiTvApresentacao,
} from "./actions";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    categoria?: string;
    erro?: string;
    sucesso?: string;
    avanco?: string;
  }>;
};

const funcoes = ["organizador", "escritorio", "locutor"];

const nomesEstado: Record<string, string> = {
  aguardando: "Aguardando",
  reservada: "Retorno liberado",
  chamada: "Chamada",
  em_corrida: "Em corrida",
  retorno_pendente: "Retorno pendente",
  concluida: "Concluída",
  encaminhada: "Encaminhada",
  rabo_da_gata: "Rabo da Gata",
};

const erros: Record<string, string> = {
  acesso: "Sua função neste evento não permite essa operação.",
  autorizacao: "Não foi possível confirmar a autorização para operar a Pista.",
  campos: "Confira os campos e tente novamente.",
  "boi-tv": "Falha ao encaminhar apresentacao para o BOI TV.",
  "pontuacao-max": "A pontuação de cada corrida deve ser de no máximo 40 pontos.",
  estado: "O estado da fila ou da posição mudou. Atualize a página antes de tentar novamente.",
  operacao: "A operação falhou. Nenhum sucesso foi confirmado; atualize e tente novamente.",
  rpc: "As RPCs da Pista não estão disponíveis. A migration precisa ser revisada e aplicada antes da operação.",
  "sem-posicao": "A posição reservada para este Retorno não está disponível. O Retorno permanece pendente.",
  "sem-proximo": "Não há rodízio planejado seguinte. O Retorno permanece pendente e nenhuma vaga foi consumida.",
};

const sucessos: Record<string, string> = {
  planejado: "Rodízio planejado.",
  iniciado: "Rodízio iniciado.",
  chamada: "Nova chamada registrada.",
  corrida: "Corrida iniciada.",
  resultado: "Resultado registrado.",
  retorno: "Retorno registrado; o boi permanece reservado para esta corrida.",
  "rabo-da-gata": "Corrida encaminhada ao fim da fila sem reserva antecipada.",
  "boi-tv": "Apresentacao encaminhada para analise BOI TV.",
  "retorno-liberado": "Retorno encaminhado conforme o destino escolhido.",
  configuracao: "Configuração de substituição atualizada.",
};

function camposEscopo(eventoId: string, categoriaId: string) {
  return (
    <>
      <input type="hidden" name="evento_id" value={eventoId} />
      <input type="hidden" name="categoria_id" value={categoriaId} />
    </>
  );
}

export default async function PistaPage({ params, searchParams }: Props) {
  const { id: eventoId } = await params;
  const { categoria: categoriaSelecionada, erro, sucesso, avanco } =
    await searchParams;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { data: perfil, error: erroPerfil } = await supabase
    .from("perfis")
    .select("parque_id")
    .eq("id", user.id)
    .single();

  if (erroPerfil || !perfil?.parque_id) {
    redirect("/painel");
  }

  const { data: evento, error: erroEvento } = await supabase
    .from("eventos")
    .select("id, nome, formato_competicao")
    .eq("id", eventoId)
    .eq("parque_id", perfil.parque_id)
    .maybeSingle();

  if (erroEvento) {
    return <main className="mx-auto min-h-screen max-w-5xl bg-stone-50 px-4 py-10 sm:px-8">
      <p role="alert" className="rounded-lg bg-amber-50 p-4 text-amber-950">Não foi possível carregar o formato da competição. Verifique se a migration de Tropa de Elite foi aplicada.</p>
    </main>;
  }
  if (!evento) {
    notFound();
  }
  if (evento.formato_competicao === "tropa_de_elite") {
    return <main className="mx-auto min-h-screen max-w-5xl bg-stone-50 px-4 py-10 sm:px-8">
      <Link href={`/eventos/${eventoId}`} className="text-sm text-stone-600 underline">Voltar ao evento</Link>
      <section className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 p-5">
        <h1 className="text-2xl font-bold text-emerald-950">Tropa de Elite · fase eliminatória</h1>
        <p className="mt-2 text-emerald-950">A Pista de rodízios não se aplica a este formato. Use o chaveamento para disputar diretamente a fase eliminatória.</p>
        <Link href={`/eventos/${eventoId}/x1`} className="mt-4 inline-flex rounded-lg bg-emerald-800 px-5 py-3 font-bold text-white">Abrir chave eliminatória</Link>
      </section>
    </main>;
  }

  const { data: categorias, error: erroCategorias } = await supabase
    .from("categorias")
    .select("id, nome, ordem")
    .eq("evento_id", evento.id)
    .order("ordem", { ascending: true });

  if (erroCategorias) {
    console.error("Erro ao carregar categorias da Pista:", erroCategorias);
  }

  const categoria = categorias?.find(
    (item) => item.id === categoriaSelecionada
  );
  const categoriaId = categoria?.id;
  let autorizado = false;
  let podeOrganizar = false;
  let podeOperar = false;

  if (categoriaId) {
    const [acesso, organizador, locutor] = await Promise.all([
      supabase.rpc("pista_tem_funcao", {
        p_evento_id: evento.id,
        p_funcoes: funcoes,
      }),
      supabase.rpc("pista_tem_funcao", {
        p_evento_id: evento.id,
        p_funcoes: ["organizador"],
      }),
      supabase.rpc("pista_tem_funcao", {
        p_evento_id: evento.id,
        p_funcoes: ["locutor"],
      }),
    ]);

    if (acesso.error || organizador.error || locutor.error) {
      console.error("Erro ao verificar funções da Pista:", {
        acesso: acesso.error,
        organizador: organizador.error,
        locutor: locutor.error,
      });
    } else {
      autorizado = Boolean(acesso.data);
      podeOrganizar = Boolean(organizador.data);
      podeOperar = Boolean(organizador.data || locutor.data);
    }
  }

  let duplas: Array<{
    id: string;
    numero_senha: number;
    puxador_id: string;
    status_pagamento: string;
    created_at: string;
  }> = [];
  let competidores: Array<{ id: string; nome: string }> = [];
  let rodizios: Array<{
    id: string;
    numero: number;
    quantidade_bois: number;
    estado: string;
    iniciado_em: string | null;
  }> = [];
  let filas: Array<{
    id: string;
    rodizio_id: string;
    dupla_id: string;
    numero_corrida: number;
    ordem: number;
    estado: string;
    posicao_boi: number | null;
    competidor_id: string | null;
  }> = [];
  let posicoes: Array<{
    numero: number;
    estado: string;
    fila_id: string | null;
  }> = [];
  let resultados: Array<{
    dupla_id: string;
    numero_corrida: number;
    resultado: string;
    pontuacao: number;
  }> = [];
  let ocorrencias: Array<{ id: string; fila_id: string; tipo: string }> = [];
  let permiteSubstituicao = false;
  let boiTvHabilitado = false;
  let boiTvRuns: Array<{ id: string; dupla_id: string; numero_corrida: number; estado: string }> = [];
  let boiTvReviewedRunIds = new Set<string>();
  let erroDados = false;

  if (categoriaId && autorizado) {
    const [
      duplasResult,
      competidoresResult,
      rodiziosResult,
      filasResult,
      resultadosResult,
      ocorrenciasResult,
      configResult,
    ] = await Promise.all([
      supabase
        .from("duplas")
        .select("id, numero_senha, puxador_id, status_pagamento, created_at")
        .eq("evento_id", evento.id)
        .eq("categoria_id", categoriaId)
        .neq("status_pagamento", "cancelado")
        .order("numero_senha", { ascending: true })
        .order("created_at", { ascending: true }),
      supabase
        .from("competidores")
        .select("id, nome")
        .eq("parque_id", perfil.parque_id)
        .order("nome", { ascending: true }),
      supabase
        .from("pista_rodizios")
        .select("id, numero, quantidade_bois, estado, iniciado_em")
        .eq("evento_id", evento.id)
        .eq("categoria_id", categoriaId)
        .order("numero", { ascending: true }),
      supabase
        .from("pista_fila")
        .select(
          "id, rodizio_id, dupla_id, numero_corrida, ordem, estado, posicao_boi, competidor_id"
        )
        .eq("evento_id", evento.id)
        .eq("categoria_id", categoriaId)
        .order("ordem", { ascending: true }),
      supabase
        .from("pista_resultados_vigentes")
        .select("dupla_id, numero_corrida, resultado, pontuacao")
        .eq("evento_id", evento.id)
        .eq("categoria_id", categoriaId),
      supabase
        .from("pista_ocorrencias")
        .select("id, fila_id, tipo")
        .eq("evento_id", evento.id)
        .eq("categoria_id", categoriaId)
        .eq("tipo", "retorno"),
      supabase
        .from("pista_evento_config")
        .select("permite_substituicao")
        .eq("evento_id", evento.id)
        .maybeSingle(),
    ]);

    const queryErrors = [
      duplasResult.error,
      competidoresResult.error,
      rodiziosResult.error,
      filasResult.error,
      resultadosResult.error,
      ocorrenciasResult.error,
      configResult.error,
    ].filter(Boolean);

    if (queryErrors.length > 0) {
      erroDados = true;
      console.error("Erro ao carregar estado persistido da Pista:", queryErrors);
    } else {
      duplas = duplasResult.data ?? [];
      competidores = competidoresResult.data ?? [];
      rodizios = rodiziosResult.data ?? [];
      filas = filasResult.data ?? [];
      resultados = resultadosResult.data ?? [];
      ocorrencias = ocorrenciasResult.data ?? [];
      permiteSubstituicao =
        configResult.data?.permite_substituicao ?? false;
    }

    const rodizioAtivo = rodizios.find(
      (item) => item.estado === "em_andamento"
    );

    if (rodizioAtivo) {
      const { data, error: erroPosicoes } = await supabase
        .from("pista_posicoes")
        .select("numero, estado, fila_id")
        .eq("rodizio_id", rodizioAtivo.id)
        .order("numero", { ascending: true });

      if (erroPosicoes) {
        erroDados = true;
        console.error("Erro ao carregar posições da Pista:", erroPosicoes);
      } else {
        posicoes = data ?? [];
      }
    }

    const [{ data: opsData }, { data: boiTvData }] = await Promise.all([
      supabase.rpc("pista_ops_state", { p_evento_id: evento.id, p_categoria_id: categoriaId }),
      supabase.rpc("pista_ops_boi_tv_estado", { p_evento_id: evento.id, p_categoria_id: categoriaId }),
    ]);
    const opsState = opsData as { rodizios?: Array<{ corridas?: Array<{ id: string; dupla_id: string; numero_corrida: number; estado: string }> }> } | null;
    const tvState = boiTvData as { habilitado?: boolean; revisoes?: Array<{ corrida_id: string }> } | null;
    boiTvHabilitado = tvState?.habilitado === true;
    boiTvRuns = (opsState?.rodizios ?? []).flatMap((round) => round.corridas ?? []);
    boiTvReviewedRunIds = new Set((tvState?.revisoes ?? []).map((review) => review.corrida_id));
  }

  const sucessoTexto = sucesso ? sucessos[sucesso] : undefined;
  const activeRodizio = rodizios.find(
    (item) => item.estado === "em_andamento"
  );
  const proximosRodizios = rodizios.filter(
    (item) => item.estado === "planejado"
  );
  const proximoRodizio = proximosRodizios[0];
  const duplaPorId = new Map(duplas.map((dupla) => [dupla.id, dupla]));
  const competidorPorId = new Map(
    competidores.map((competidor) => [competidor.id, competidor])
  );
  const resultadosPorCorrida = new Map(
    resultados.map((resultado) => [
      `${resultado.dupla_id}:${resultado.numero_corrida}`,
      resultado,
    ])
  );
  const ocorrenciaPorFila = new Map(
    ocorrencias.map((ocorrencia) => [ocorrencia.fila_id, ocorrencia])
  );
  const retornosPendentes = filas.filter(
    (fila) => fila.estado === "retorno_pendente"
  );
  const filasDoRodizioAtivo = filas
    .filter((fila) => fila.rodizio_id === activeRodizio?.id)
    .sort((a, b) => a.ordem - b.ordem);
  const filasDoProximoRodizio = proximoRodizio
    ? filas.filter((fila) => fila.rodizio_id === proximoRodizio.id)
    : [];
  return (
    <main className="mx-auto min-h-screen w-full max-w-5xl px-4 py-6 sm:px-8">
      <Link href="/painel" className="text-sm text-gray-600 underline">
        Voltar aos eventos
      </Link>

      <header className="mt-5">
        <p className="text-sm text-muted-foreground">{evento.nome}</p>
        <h1 className="text-3xl font-semibold">Pista</h1>
      </header>

      {erro && (
        <p role="alert" className="mt-5 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {erros[erro] ?? "A operação não foi concluída."}
        </p>
      )}
      {sucessoTexto && (
        <p role="status" className="mt-5 rounded-md bg-green-50 p-3 text-sm text-green-800">
          {sucessoTexto}
        </p>
      )}
      {avanco === "sem-chamada" && (
        <p role="status" className="mt-5 rounded-md border p-3 text-sm">
          Nenhuma inscrição foi chamada. Confira a fila, as vagas livres e se
          existe rodízio planejado para receber corridas encaminhadas.
        </p>
      )}
      {avanco === "sem-vaga" && (
        <p role="alert" className="mt-5 rounded-md bg-amber-50 p-3 text-sm text-amber-900">
          Não foi possível iniciar a corrida porque a vaga reservada não está
          disponível. A fila não foi confirmada como alterada; atualize a página.
        </p>
      )}

      {erroCategorias ? (
        <p role="alert" className="mt-6 text-red-700">
          Não foi possível carregar as categorias do evento.
        </p>
      ) : !categorias?.length ? (
        <p className="mt-6 rounded-lg border p-5 text-muted-foreground">
          Este evento ainda não tem categorias.
        </p>
      ) : (
        <nav aria-label="Categorias da Pista" className="mt-6 flex flex-wrap gap-2">
          {categorias.map((item) => (
            <Link
              key={item.id}
              href={`/eventos/${evento.id}/pista?categoria=${item.id}`}
              aria-current={item.id === categoriaId ? "page" : undefined}
              className={`rounded-md border px-3 py-2 text-sm ${
                item.id === categoriaId
                  ? "bg-primary text-primary-foreground"
                  : "hover:bg-muted"
              }`}
            >
              {item.nome}
            </Link>
          ))}
        </nav>
      )}

      {!categoriaId && (
        <p className="mt-6 rounded-lg border p-5 text-muted-foreground">
          Selecione uma categoria para consultar a fila e operar a Pista.
        </p>
      )}

      {categoriaId && !autorizado && (
        <section className="mt-6 rounded-lg border border-amber-300 bg-amber-50 p-5">
          <h2 className="font-semibold">Acesso à Pista não configurado</h2>
          <p className="mt-2 text-sm">
            A autenticação e o papel do parque, por si sós, não autorizam a
            operação. É necessária uma atribuição ativa de organizador,
            escritório ou locutor neste evento.
          </p>
          <p className="mt-2 text-sm">
            O bootstrap do primeiro organizador ainda exige um processo
            confiável; esta página não usa service role nem concede acesso
            automaticamente.
          </p>
        </section>
      )}

      {categoriaId && autorizado && !podeOperar && (
        <section className="mt-6 rounded-lg border p-5">
          <h2 className="font-semibold">Função sem operação de pista</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Sua função atual pode consultar apenas os dados que as policies
            permitem; as operações de rodízio e corrida são restritas a
            organizador e locutor.
          </p>
        </section>
      )}

      {categoria && autorizado && podeOperar && (
        <>
          <h2 className="mt-6 text-xl font-semibold">{categoria.nome}</h2>

          {erroDados ? (
            <p role="alert" className="mt-4 rounded-md bg-red-50 p-4 text-red-800">
              Não foi possível carregar o estado operacional da Pista. Verifique
              as RPCs, tabelas e policies da migration antes de tentar novamente.
            </p>
          ) : (
            <>
              {podeOrganizar && (
                <section className="mt-5 grid gap-4 md:grid-cols-2">
                  <form action={planejarRodizio} className="space-y-3 rounded-lg border p-4">
                    {camposEscopo(evento.id, categoria.id)}
                    <h3 className="font-medium">Planejar rodízio</h3>
                    <label className="block text-sm" htmlFor="quantidade_bois">
                      Quantidade de bois deste rodízio
                    </label>
                    <input
                      id="quantidade_bois"
                      name="quantidade_bois"
                      type="number"
                      min="1"
                      step="1"
                      required
                      className="w-full rounded-md border px-3 py-2"
                    />
                    <button className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                      Planejar
                    </button>
                  </form>

                  <form action={configurarSubstituicao} className="space-y-3 rounded-lg border p-4">
                    {camposEscopo(evento.id, categoria.id)}
                    <h3 className="font-medium">Substituição de competidor</h3>
                    <label className="flex items-start gap-3 text-sm">
                      <input
                        type="checkbox"
                        name="permite_substituicao"
                        defaultChecked={permiteSubstituicao}
                        className="mt-1"
                      />
                      Permitir substituição nesta Pista. O competidor que correr
                      será registrado em cada corrida.
                    </label>
                    <button className="rounded-md border px-4 py-2 text-sm font-medium">
                      Salvar configuração
                    </button>
                  </form>
                </section>
              )}

              {!activeRodizio && proximoRodizio && (
                <section className="mt-5 rounded-lg border p-4">
                  <h3 className="font-medium">
                    Iniciar rodízio {proximoRodizio.numero}
                  </h3>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Capacidade: {proximoRodizio.quantidade_bois} bois. A fila
                    inicial segue senha crescente e depois data de cadastro.
                  </p>
                  {filasDoProximoRodizio.length > 0 ? (
                    <p className="mt-3 text-sm">
                      Este rodízio já tem corridas encaminhadas e não pode ser
                      inicializado novamente pela seleção inicial.
                    </p>
                  ) : duplas.length === 0 ? (
                    <p className="mt-3 text-sm">
                      Não há inscrições não canceladas nesta categoria.
                    </p>
                  ) : (
                    <form action={iniciarRodizio} className="mt-4 space-y-3">
                      {camposEscopo(evento.id, categoria.id)}
                      <input
                        type="hidden"
                        name="rodizio_id"
                        value={proximoRodizio.id}
                      />
                      <fieldset className="max-h-64 space-y-2 overflow-auto rounded-md border p-3">
                        <legend className="px-1 text-sm font-medium">
                          Inscrições que terão as corridas 1 e 2 na fila
                        </legend>
                        {duplas.map((dupla) => (
                          <label
                            key={dupla.id}
                            className="flex items-center gap-2 text-sm"
                          >
                            <input
                              type="checkbox"
                              name="dupla_ids"
                              value={dupla.id}
                              defaultChecked
                            />
                            Senha {dupla.numero_senha} ·{" "}
                            {competidorPorId.get(dupla.puxador_id)?.nome ?? "Competidor"}
                          </label>
                        ))}
                      </fieldset>
                      <button className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                        Iniciar fila
                      </button>
                    </form>
                  )}
                </section>
              )}

              <section className="mt-6 rounded-lg border p-4">
                <h3 className="font-semibold">Rodízio e posições</h3>
                {!activeRodizio ? (
                  <p className="mt-2 text-sm text-muted-foreground">
                    Nenhum rodízio está em andamento.
                  </p>
                ) : (
                  <>
                    <p className="mt-2 text-sm">
                      Rodízio {activeRodizio.numero} · {activeRodizio.quantidade_bois}{" "}
                      bois · iniciado{" "}
                      {activeRodizio.iniciado_em
                        ? new Date(activeRodizio.iniciado_em).toLocaleString("pt-BR")
                        : "—"}
                    </p>
                    <ol className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-6">
                      {posicoes.map((posicao) => {
                        const fila = filas.find((item) => item.id === posicao.fila_id);
                        const dupla = fila ? duplaPorId.get(fila.dupla_id) : undefined;
                        const emRetorno = fila?.estado === "retorno_pendente";
                        return (
                          <li
                            key={posicao.numero}
                            className="rounded-md border p-3 text-sm"
                          >
                            <span className="font-semibold">Boi {posicao.numero}</span>
                            <span className="mt-1 block">
                              {posicao.estado === "livre"
                                ? "Livre"
                                : posicao.estado === "consumida"
                                  ? "Consumido"
                                  : emRetorno
                                    ? `Reservado · Retorno senha ${dupla?.numero_senha ?? ""}`
                                    : `Reservado · senha ${dupla?.numero_senha ?? ""}`}
                            </span>
                          </li>
                        );
                      })}
                    </ol>
                    {podeOperar && (
                      <form action={chamarProxima} className="mt-4">
                        {camposEscopo(evento.id, categoria.id)}
                        <input
                          type="hidden"
                          name="rodizio_id"
                          value={activeRodizio.id}
                        />
                        <button className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                          Chamar próxima inscrição / avançar fila
                        </button>
                      </form>
                    )}
                  </>
                )}
              </section>

              <section className="mt-6">
                <h3 className="text-lg font-semibold">Fila do rodízio atual</h3>
                {!activeRodizio || filasDoRodizioAtivo.length === 0 ? (
                  <p className="mt-2 rounded-lg border p-4 text-sm text-muted-foreground">
                    Ainda não há corridas neste rodízio.
                  </p>
                ) : (
                  <ol className="mt-3 space-y-3">
                    {filasDoRodizioAtivo.map((fila) => {
                      const dupla = duplaPorId.get(fila.dupla_id);
                      const competidor = fila.competidor_id
                        ? competidorPorId.get(fila.competidor_id)
                        : undefined;
                      const inscrito = dupla
                        ? competidorPorId.get(dupla.puxador_id)
                        : undefined;
                      const resultado = resultadosPorCorrida.get(
                        `${fila.dupla_id}:${fila.numero_corrida}`
                      );
                      const opsRun = boiTvRuns.find((run) => run.dupla_id === fila.dupla_id && run.numero_corrida === fila.numero_corrida && run.estado === (resultado?.resultado === "zero" ? "zero" : "valeu_boi"));
                      return (
                        <li key={fila.id} className="rounded-lg border p-4">
                          <div className="flex flex-wrap items-baseline justify-between gap-2">
                            <h4 className="font-medium">
                              Senha {dupla?.numero_senha ?? "—"} · Corrida{" "}
                              {fila.numero_corrida} de 2
                            </h4>
                            <span className="text-sm text-muted-foreground">
                              {nomesEstado[fila.estado] ?? fila.estado}
                              {fila.posicao_boi ? ` · Boi ${fila.posicao_boi}` : ""}
                            </span>
                          </div>
                          {resultado && (
                            <p className="mt-2 text-sm">
                              Resultado vigente: {resultado.resultado === "zero" ? "Zero" : "Valeu Boi"}{" "}
                              · {resultado.pontuacao} pontos
                            </p>
                          )}
                          {boiTvHabilitado && resultado && opsRun && !boiTvReviewedRunIds.has(opsRun.id) && autorizado && (
                            <div className="mt-3 flex flex-wrap items-center gap-2 rounded-lg bg-amber-50 p-3 text-sm">
                              <span>Boi TV · enviar esta apresentação para análise</span>
                              {resultado.resultado === "zero" ? (
                                <form action={solicitarBoiTvApresentacao}>
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input type="hidden" name="corrida_id" value={opsRun.id} />
                                  <input type="hidden" name="tipo_solicitacao" value="a_favor" />
                                  <input type="hidden" name="reclamante_dupla_id" value={fila.dupla_id} />
                                  <button className="rounded border border-amber-700 px-3 py-2 font-semibold text-amber-950">Boi a favor</button>
                                </form>
                              ) : (
                                <form action={solicitarBoiTvApresentacao} className="flex flex-wrap items-center gap-2">
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input type="hidden" name="corrida_id" value={opsRun.id} />
                                  <input type="hidden" name="tipo_solicitacao" value="contra_terceiro" />
                                  <label>Solicitante<select name="reclamante_dupla_id" required defaultValue="" className="ml-2 h-10 rounded border px-2"><option value="" disabled>Escolher senha</option>{duplas.filter((item) => item.id !== fila.dupla_id).map((item) => <option key={item.id} value={item.id}>Senha {item.numero_senha}</option>)}</select></label>
                                  <button className="rounded border border-amber-700 px-3 py-2 font-semibold text-amber-950">Boi contra</button>
                                </form>
                              )}
                            </div>
                          )}
                          {competidor && (
                            <p className="mt-2 text-sm">
                              Correu: {competidor.nome}
                              {inscrito && inscrito.id !== competidor.id
                                ? ` (inscrito: ${inscrito.nome})`
                                : ""}
                            </p>
                          )}

                          {fila.estado === "chamada" && podeOperar && (
                            <div className="mt-4 grid gap-3 lg:grid-cols-2">
                              <form action={iniciarCorrida} className="space-y-2">
                                {camposEscopo(evento.id, categoria.id)}
                                <input
                                  type="hidden"
                                  name="fila_id"
                                  value={fila.id}
                                />
                                <label className="block text-sm font-medium">
                                  Competidor que vai correr
                                  <select
                                    name="competidor_id"
                                    required
                                    defaultValue={dupla?.puxador_id ?? ""}
                                    className="mt-1 w-full rounded-md border px-3 py-2"
                                  >
                                    <option value="" disabled>
                                      Selecione
                                    </option>
                                    {competidores
                                      .filter(
                                        (item) =>
                                          permiteSubstituicao ||
                                          item.id === dupla?.puxador_id
                                      )
                                      .map((item) => (
                                        <option key={item.id} value={item.id}>
                                          {item.nome}
                                        </option>
                                      ))}
                                  </select>
                                </label>
                                <button className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                                  Iniciar corrida
                                </button>
                              </form>
                              <form action={registrarRaboDaGata} className="self-end">
                                {camposEscopo(evento.id, categoria.id)}
                                <input
                                  type="hidden"
                                  name="fila_id"
                                  value={fila.id}
                                />
                                <button className="rounded-md border px-4 py-2 text-sm font-medium">
                                  Rabo da Gata · enviar ao fim
                                </button>
                              </form>
                            </div>
                          )}

                          {fila.estado === "em_corrida" && podeOperar && (
                            <div className="mt-4 grid gap-3 lg:grid-cols-2">
                              <form action={registrarResultado} className="space-y-2">
                                {camposEscopo(evento.id, categoria.id)}
                                <input
                                  type="hidden"
                                  name="fila_id"
                                  value={fila.id}
                                />
                                <input
                                  type="hidden"
                                  name="resultado"
                                  value="valeu_boi"
                                />
                                <label className="block text-sm font-medium">
                                  Pontuação informada pelo juiz
                                  <input
                                    type="number"
                                    name="pontuacao"
                                    step="any"
                                    min="0"
                                    max="40"
                                    required
                                    className="mt-1 w-full rounded-md border px-3 py-2"
                                  />
                                  <span className="mt-1 block text-xs text-gray-600">Máximo de 40 pontos por corrida.</span>
                                </label>
                                <button className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                                  Registrar Valeu Boi
                                </button>
                              </form>
                              <div className="flex flex-col items-start gap-3">
                                <form action={registrarResultado}>
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input
                                    type="hidden"
                                    name="fila_id"
                                    value={fila.id}
                                  />
                                  <input
                                    type="hidden"
                                    name="resultado"
                                    value="zero"
                                  />
                                  <input
                                    type="hidden"
                                    name="pontuacao"
                                    value="0"
                                  />
                                  <button className="rounded-md border px-4 py-2 text-sm font-medium">
                                    Registrar Zero (0 pontos)
                                  </button>
                                </form>
                                <form action={registrarRetorno}>
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input
                                    type="hidden"
                                    name="fila_id"
                                    value={fila.id}
                                  />
                                  <button className="rounded-md border border-amber-400 px-4 py-2 text-sm font-medium">
                                    Registrar Retorno
                                  </button>
                                </form>
                              </div>
                            </div>
                          )}
                        </li>
                      );
                    })}
                  </ol>
                )}
              </section>

              <section className="mt-6">
                <h3 className="text-lg font-semibold">Retornos pendentes</h3>
                {!retornosPendentes.length ? (
                  <p className="mt-2 rounded-lg border p-4 text-sm text-muted-foreground">
                    Não há Retornos pendentes nesta categoria.
                  </p>
                ) : (
                  <ul className="mt-3 space-y-3">
                    {retornosPendentes.map((fila) => {
                      const dupla = duplaPorId.get(fila.dupla_id);
                      const ocorrencia = ocorrenciaPorFila.get(fila.id);
                      const rodizioOriginal = rodizios.find(
                        (rodizio) => rodizio.id === fila.rodizio_id
                      );
                      const podeVoltarAoAtual =
                        rodizioOriginal?.estado === "em_andamento";

                      return (
                        <li key={fila.id} className="rounded-lg border p-4">
                          <p className="font-medium">
                            Senha {dupla?.numero_senha ?? "—"} · Corrida{" "}
                            {fila.numero_corrida} de 2 · Rodízio{" "}
                            {rodizioOriginal?.numero ?? "—"}
                          </p>
                          <p className="mt-1 text-sm text-muted-foreground">
                            A posição original permanece reservada até esta
                            corrida ser realizada. O Retorno não cria uma
                            terceira corrida.
                          </p>
                          {podeOperar && ocorrencia && (
                            <div className="mt-3 flex flex-wrap gap-2">
                              {podeVoltarAoAtual && (
                                <form action={liberarRetorno}>
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input
                                    type="hidden"
                                    name="ocorrencia_id"
                                    value={ocorrencia.id}
                                  />
                                  <input
                                    type="hidden"
                                    name="destino"
                                    value="rodizio_atual"
                                  />
                                  <button className="rounded-md border px-3 py-2 text-sm">
                                    Liberar na vaga original
                                  </button>
                                </form>
                              )}
                              {proximoRodizio && (
                                <form action={liberarRetorno}>
                                  {camposEscopo(evento.id, categoria.id)}
                                  <input
                                    type="hidden"
                                    name="ocorrencia_id"
                                    value={ocorrencia.id}
                                  />
                                  <input
                                    type="hidden"
                                    name="destino"
                                    value="proximo_rodizio"
                                  />
                                  <button className="rounded-md border px-3 py-2 text-sm">
                                    Liberar para o próximo rodízio
                                  </button>
                                </form>
                              )}
                              {!proximoRodizio && !podeVoltarAoAtual && (
                                <p className="text-sm text-amber-800">
                                  Planeje outro rodízio antes de decidir o
                                  destino. O Retorno permanece pendente.
                                </p>
                              )}
                            </div>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                )}
              </section>

              <section className="mt-6 rounded-lg border p-4">
                <h3 className="font-semibold">Parcial da categoria</h3>
                {!duplas.length ? (
                  <p className="mt-2 text-sm text-muted-foreground">
                    Não há inscrições não canceladas.
                  </p>
                ) : (
                  <ol className="mt-3 space-y-2">
                    {duplas.map((dupla) => {
                      const corridasDupla = resultados.filter(
                        (item) => item.dupla_id === dupla.id
                      );
                      const pontos = corridasDupla.reduce(
                        (total, item) => total + Number(item.pontuacao),
                        0
                      );
                      return (
                        <li
                          key={dupla.id}
                          className="flex flex-wrap justify-between gap-2 border-b py-2 text-sm last:border-0"
                        >
                          <span>
                            Senha {dupla.numero_senha} · {corridasDupla.length}/2 corridas
                          </span>
                          <span>{pontos} pontos</span>
                        </li>
                      );
                    })}
                  </ol>
                )}
              </section>

              <section className="mt-6">
                <h3 className="text-lg font-semibold">Histórico de rodízios</h3>
                {!rodizios.length ? (
                  <p className="mt-2 rounded-lg border p-4 text-sm text-muted-foreground">
                    Nenhum rodízio planejado.
                  </p>
                ) : (
                  <ul className="mt-3 space-y-2">
                    {rodizios.map((rodizio) => (
                      <li
                        key={rodizio.id}
                        className="flex flex-wrap justify-between gap-2 rounded-md border p-3 text-sm"
                      >
                        <span>
                          Rodízio {rodizio.numero} · {rodizio.quantidade_bois} bois
                        </span>
                        <span>{nomesEstado[rodizio.estado] ?? rodizio.estado}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </section>
            </>
          )}
        </>
      )}
    </main>
  );
}
