"use client";

import { useRef, useState } from "react";
import { Check, Filter, RotateCcw, Search, UserRound, UsersRound, Trophy, Rabbit } from "lucide-react";
import { inscreverCompetidor } from "./actions";
import styles from "../escritorio.module.css";

type Categoria = { id: string; nome: string };

export function FormularioInscricao({
  eventoId,
  categorias,
  permiteGerenciarCategorias = false,
}: {
  eventoId: string;
  categorias: Categoria[];
  permiteGerenciarCategorias?: boolean;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [modalAberto, setModalAberto] = useState(false);
  const [status, setStatus] = useState("");

  function limpar() {
    formRef.current?.reset();
    setStatus("");
    setModalAberto(false);
  }

  return (
    <section className={`${styles.card} ${styles.registrationCard}`} aria-labelledby="registration-title">
      <div className={styles.sectionHeading}>
        <Filter className={styles.headingIcon} aria-hidden="true" />
        <h1 id="registration-title">Filtros de Busca</h1>
        <span className={styles.headingRule} />
      </div>

      <form ref={formRef} action={inscreverCompetidor}>
        <input type="hidden" name="evento_id" value={eventoId} />
        <div className={styles.fields}>
          <label className={styles.field}>
            <span className={styles.label}>Senha</span>
            <input className={styles.input} name="numero_senha" type="text" inputMode="numeric" maxLength={500} required placeholder="Ex.: 1, 2" aria-describedby="senha-help" />
            <span id="senha-help" className={styles.optional}>Para mais de uma senha, separe os números por vírgula.</span>
          </label>

          <label className={styles.field}>
            <span className={styles.label}>Nome do Vaqueiro</span>
            <span className={styles.inputWrap}>
              <UserRound className={styles.fieldIcon} aria-hidden="true" />
              <input className={styles.input} name="nome" required maxLength={120} placeholder="Nome do Vaqueiro" />
            </span>
          </label>

          <label className={styles.field}>
            <span className={styles.label}>Nome da Equipe <span className={styles.optional}>Opcional</span></span>
            <span className={styles.inputWrap}>
              <UsersRound className={styles.fieldIcon} aria-hidden="true" />
              <input className={styles.input} name="nome_equipe" maxLength={120} placeholder="Nome da Equipe" />
            </span>
          </label>

          <label className={`${styles.field} ${styles.fieldCategory}`}>
            <span className={styles.label}>
              Categoria
              {permiteGerenciarCategorias && <a className={styles.optional} href={`/eventos/${eventoId}/duplas?categoria=novo`}>Gerenciar</a>}
            </span>
            <span className={styles.inputWrap}>
              <Trophy className={styles.fieldIcon} aria-hidden="true" />
              <select className={styles.select} name="categoria_id" required defaultValue="">
                <option value="" disabled>Selecione</option>
                {categorias.map((categoria) => <option key={categoria.id} value={categoria.id}>{categoria.nome}</option>)}
              </select>
            </span>
          </label>

          <label className={`${styles.field} ${styles.fieldHorse}`}>
            <span className={styles.label}>Nome do Cavalo <span className={styles.optional}>Opcional</span></span>
            <span className={styles.inputWrap}>
              <Rabbit className={styles.fieldIcon} aria-hidden="true" />
              <input className={styles.input} name="nome_cavalo" maxLength={120} placeholder="Nome do Cavalo" />
            </span>
          </label>
        </div>

        <div className={styles.actions}>
          <button type="reset" onClick={limpar} className={`${styles.button} ${styles.buttonClear}`}>
            <RotateCcw aria-hidden="true" /> Limpar
          </button>
          <button type="submit" name="modo" value="reservar" className={`${styles.button} ${styles.buttonReserve}`}>
            <Search aria-hidden="true" /> Reservar
          </button>
          <button type="button" onClick={() => setModalAberto(true)} className={`${styles.button} ${styles.buttonConfirm}`}>
            <Check aria-hidden="true" /> Confirma
          </button>
        </div>

        {modalAberto && (
          <div
            className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4"
            onMouseDown={(event) => { if (event.target === event.currentTarget) setModalAberto(false); }}
            onKeyDown={(event) => { if (event.key === "Escape") setModalAberto(false); }}
          >
            <section role="dialog" aria-modal="true" aria-labelledby="payment-title" className="w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl">
              <h2 id="payment-title" className="text-lg font-semibold text-gray-950">Status do pagamento</h2>
              <p className="mt-1 text-sm text-gray-600">Selecione a situação para confirmar a inscrição.</p>
              <label className="mt-5 grid gap-2 text-sm font-medium">
                Status do pagamento
                <select name="status_pagamento" value={status} onChange={(event) => setStatus(event.target.value)} autoFocus required className="h-10 rounded-md border border-gray-300 px-3">
                  <option value="" disabled>Selecione</option>
                  <option value="pendente">Pendente</option>
                  <option value="pago">Pago</option>
                  <option value="isento">Isento</option>
                </select>
              </label>
              {status === "isento" && <label className="mt-4 grid gap-2 text-sm font-medium">Motivo da isenção<input name="motivo_isencao" required maxLength={500} className="h-10 rounded-md border border-gray-300 px-3" placeholder="Informe o motivo" /></label>}
              <div className="mt-6 flex justify-end gap-3">
                <button type="button" onClick={() => setModalAberto(false)} className="rounded-md border px-4 py-2 text-sm font-medium text-gray-700">Voltar</button>
                <button type="submit" className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700">Confirmar inscrição</button>
              </div>
            </section>
          </div>
        )}
      </form>
    </section>
  );
}
