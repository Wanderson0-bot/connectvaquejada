"use client";

import Link from "next/link";
import Image from "next/image";
import { MoreHorizontal, Printer, Search, Trophy } from "lucide-react";
import { useEffect, useState } from "react";
import { AtualizacaoPagamentoForm } from "./AtualizacaoPagamentoForm";
import { ConfirmForm } from "@/components/ConfirmForm";
import { excluirInscricaoNoEscritorio } from "./actions";
import styles from "./escritorio.module.css";
import printStyles from "./inscricoes.module.css";

export type Inscricao = {
  id: string;
  competidorId: string;
  numeroSenha: number;
  categoria: string;
  competidor: string;
  nomeCavalo: string | null;
  nomeEquipe: string | null;
  statusPagamento: string;
  motivoIsencao: string | null;
};

type Props = {
  eventoId: string;
  eventoNome: string;
  eventoData: string;
  parqueNome: string;
  inscricoes: Inscricao[];
  somenteLeitura?: boolean;
};

const rotulosPagamento: Record<string, string> = { pendente: "Pendente", pago: "Pago", isento: "Isento", cancelado: "Cancelado" };

function formatarData(data: string) {
  return new Date(`${data}T12:00:00`).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
}

function formatarImpressao(data: Date) {
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(data);
}

export function ListaInscricoes({ eventoId, eventoNome, eventoData, parqueNome, inscricoes, somenteLeitura = false }: Props) {
  const [busca, setBusca] = useState("");
  const [buscaAplicada, setBuscaAplicada] = useState("");
  const [impressaoCompetidorId, setImpressaoCompetidorId] = useState<string | null>(null);
  const [inscricaoAberta, setInscricaoAberta] = useState<Inscricao | null>(null);
  const [larguraRolo, setLarguraRolo] = useState<"58" | "80">("80");
  const filtradas = inscricoes.filter((inscricao) => String(inscricao.numeroSenha).includes(buscaAplicada.trim()));
  const selecionada = inscricoes.find((inscricao) => inscricao.competidorId === impressaoCompetidorId);
  const inscricoesDoVaqueiro = selecionada
    ? inscricoes.filter((inscricao) => inscricao.competidorId === selecionada.competidorId)
    : [];

  useEffect(() => {
    if (!impressaoCompetidorId) return;
    const frame = window.requestAnimationFrame(() => window.print());
    const limparSelecao = () => setImpressaoCompetidorId(null);
    window.addEventListener("afterprint", limparSelecao);
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("afterprint", limparSelecao);
    };
  }, [impressaoCompetidorId]);

  function imprimir(id: string) {
    const inscricao = inscricoes.find((item) => item.id === id);
    if (!inscricao) return;
    setImpressaoCompetidorId(inscricao.competidorId);
  }

  return (
    <section className={`${styles.card} ${styles.listCard} ${printStyles.printArea}`} data-paper-width={larguraRolo} aria-labelledby="entries-title">
      <div className={`${styles.listHeading} ${printStyles.printHeading}`}>
        <Trophy className={styles.horseIcon} aria-hidden="true" />
        <h2 id="entries-title">Vaqueirama</h2>
        <span className={styles.headingRule} />
        <label className={`${printStyles.paperControl} ${printStyles.hideOnPrint}`}>Rolo
          <select aria-label="Largura do rolo térmico" value={larguraRolo} onChange={(event) => setLarguraRolo(event.target.value as "58" | "80")}>
            <option value="58">58 mm</option>
            <option value="80">80 mm</option>
          </select>
        </label>
      </div>

      <form className={`${printStyles.hideOnPrint} mt-3 flex max-w-[335px] gap-3`} onSubmit={(event) => { event.preventDefault(); setBuscaAplicada(busca); }}>
        <label className="relative min-w-0 flex-1">
          <span className="sr-only">Número da senha</span>
          <Search aria-hidden="true" size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
          <input type="number" min={1} value={busca} onChange={(event) => setBusca(event.target.value)} placeholder="Número da Senha" className="h-[38px] w-full rounded-[9px] border border-[#d9d9de] bg-white/90 pl-9 pr-3 text-xs outline-none focus:border-orange-600 focus:ring-2 focus:ring-orange-100" />
        </label>
        <button type="submit" className="inline-flex h-[38px] items-center gap-2 rounded-[9px] bg-[#13a45e] px-4 text-xs font-bold text-white hover:bg-[#0e8b4f]">
          <Search aria-hidden="true" size={15} /> Buscar
        </button>
      </form>

      <div className={`${styles.responsive} mt-3 overflow-x-auto`}>
        <table className={styles.table}>
          <thead><tr><th>Senha</th><th>Vaqueiro</th><th>Equipe</th><th>Categoria</th><th>Cavalo</th><th>Ação</th></tr></thead>
          <tbody>
            {filtradas.map((inscricao) => (
              <tr key={inscricao.id}>
                <td>{inscricao.numeroSenha}</td>
                <td>{inscricao.competidor}</td>
                <td>{inscricao.nomeEquipe || "—"}</td>
                <td>{inscricao.categoria}</td>
                <td>{inscricao.nomeCavalo || "—"}</td>
                <td>
                  <div className={`${printStyles.hideOnPrint} ${styles.moreActions}`}>
                    <button type="button" onClick={() => imprimir(inscricao.id)} className={styles.printButton}><Printer aria-hidden="true" /> Imprimir</button>
                    <button
                      type="button"
                      aria-label={`Mais ações para senha ${inscricao.numeroSenha}`}
                      className={styles.moreButton}
                      onClick={() => setInscricaoAberta(inscricao)}
                    >
                      <MoreHorizontal aria-hidden="true" size={17} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {inscricaoAberta && (
        <div
          className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4"
          onMouseDown={(event) => { if (event.target === event.currentTarget) setInscricaoAberta(null); }}
          onKeyDown={(event) => { if (event.key === "Escape") setInscricaoAberta(null); }}
        >
          <section role="dialog" aria-modal="true" aria-labelledby="inscricao-dialog-title" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl">
            <header className="flex items-start justify-between gap-4">
              <div>
                <h2 id="inscricao-dialog-title" className="text-xl font-bold text-stone-900">Inscrição · Senha {inscricaoAberta.numeroSenha}</h2>
                <p className="mt-1 text-sm text-stone-600">Confira os dados antes de editar ou excluir.</p>
              </div>
              <button type="button" aria-label="Fechar" onClick={() => setInscricaoAberta(null)} className="rounded-md px-2 py-1 text-xl text-stone-600 hover:bg-stone-100">×</button>
            </header>

            <dl className="mt-5 grid grid-cols-1 gap-3 rounded-xl border bg-stone-50 p-4 text-sm sm:grid-cols-2">
              <div><dt className="text-xs font-semibold text-stone-500">Evento</dt><dd className="mt-1 break-words font-medium">{eventoNome}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Data</dt><dd className="mt-1 font-medium">{formatarData(eventoData)}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Vaqueiro</dt><dd className="mt-1 break-words font-medium">{inscricaoAberta.competidor}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Categoria</dt><dd className="mt-1 break-words font-medium">{inscricaoAberta.categoria}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Equipe</dt><dd className="mt-1 break-words font-medium">{inscricaoAberta.nomeEquipe || "—"}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Cavalo</dt><dd className="mt-1 break-words font-medium">{inscricaoAberta.nomeCavalo || "—"}</dd></div>
              <div><dt className="text-xs font-semibold text-stone-500">Pagamento</dt><dd className="mt-1 font-medium">{rotulosPagamento[inscricaoAberta.statusPagamento] ?? inscricaoAberta.statusPagamento}</dd></div>
              {inscricaoAberta.motivoIsencao && <div><dt className="text-xs font-semibold text-stone-500">Motivo da isenção</dt><dd className="mt-1 break-words font-medium">{inscricaoAberta.motivoIsencao}</dd></div>}
            </dl>

            {somenteLeitura
              ? <p className="mt-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">As inscrições estão bloqueadas durante a pausa ou o encerramento.</p>
              : <AtualizacaoPagamentoForm eventoId={eventoId} duplaId={inscricaoAberta.id} statusPagamento={inscricaoAberta.statusPagamento} motivoIsencao={inscricaoAberta.motivoIsencao} />}

            <div className="mt-5 flex flex-wrap justify-end gap-2">
              <button type="button" onClick={() => setInscricaoAberta(null)} className="rounded-md border px-4 py-2 text-sm font-semibold text-stone-700 hover:bg-stone-50">Fechar</button>
              {!somenteLeitura && <Link href={`/eventos/${eventoId}/duplas/${inscricaoAberta.id}/editar`} className="rounded-md bg-[#ff7a00] px-4 py-2 text-sm font-bold text-white hover:bg-orange-700">Editar inscrição</Link>}
              {!somenteLeitura && <ConfirmForm action={excluirInscricaoNoEscritorio} message={`Excluir a inscrição da senha ${inscricaoAberta.numeroSenha}, de ${inscricaoAberta.competidor}? Ela será cancelada e removida da lista; o histórico será preservado e não haverá estorno automático.`}>
                <input type="hidden" name="evento_id" value={eventoId}/>
                <input type="hidden" name="dupla_id" value={inscricaoAberta.id}/>
                <button className="rounded-md border border-red-200 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50">Excluir inscrição</button>
              </ConfirmForm>}
            </div>
          </section>
        </div>
      )}

      {selecionada && <article className={printStyles.receipt} data-paper-width={larguraRolo} aria-label={`Comprovante de inscrições de ${selecionada.competidor}`}>
        <header className={printStyles.receiptHeader}>
          <Image src="/logo-connect-vaquejada.png" alt="Connect Vaquejada" width={300} height={154} priority unoptimized className={printStyles.receiptLogo} />
          <h1>{parqueNome}</h1>
          <p className={printStyles.receiptSubtitle}>Comprovante de inscrições</p>
        </header>

        <div className={printStyles.receiptRule} />
        <dl className={printStyles.receiptDetails}>
          <div><dt>Evento:</dt><dd>{eventoNome}</dd></div>
          <div><dt>Data do evento:</dt><dd>{formatarData(eventoData)}</dd></div>
          <div><dt>Vaqueiro:</dt><dd>{selecionada.competidor}</dd></div>
          <div><dt>Equipe/Representação:</dt><dd>{selecionada.nomeEquipe || "—"}</dd></div>
        </dl>
        <div className={printStyles.receiptRule} />

        <h2 className={printStyles.entriesTitle}>Inscrições</h2>
        <div className={printStyles.receiptEntries}>
          {inscricoesDoVaqueiro.map((inscricao) => <section key={inscricao.id} className={printStyles.receiptEntry}>
            <p className={printStyles.senha}>Senha Nº {String(inscricao.numeroSenha).padStart(4, "0")}</p>
            <dl className={printStyles.entryDetails}>
              <div><dt>Categoria:</dt><dd>{inscricao.categoria}</dd></div>
              <div><dt>Cavalo:</dt><dd>{inscricao.nomeCavalo || "—"}</dd></div>
              <div><dt>Pagamento:</dt><dd><span className={printStyles.paymentStatus}>{rotulosPagamento[inscricao.statusPagamento] ?? inscricao.statusPagamento}</span></dd></div>
            </dl>
          </section>)}
        </div>

        <div className={printStyles.receiptRule} />
        <p className={printStyles.printedAt}><Printer aria-hidden="true" /> <span>Impresso em: {formatarImpressao(new Date())}</span></p>
        <p className={printStyles.receiptFooter}>Boa sorte na pista,<br />vaqueiro!</p>
      </article>}

      {!filtradas.length && <p role="status" className={styles.empty}>{inscricoes.length ? "Nenhuma inscrição encontrada para essa senha." : "Ainda não há inscrições nesta operação."}</p>}
    </section>
  );
}
