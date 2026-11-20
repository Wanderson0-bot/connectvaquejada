"use client";

import { useState } from "react";
import { atualizarStatusPagamento } from "./actions";

type Props = {
  eventoId: string;
  duplaId: string;
  statusPagamento: string;
  motivoIsencao: string | null;
};

const statusDoMvp = ["pendente", "pago", "isento"];

export function AtualizacaoPagamentoForm({
  eventoId,
  duplaId,
  statusPagamento,
  motivoIsencao,
}: Props) {
  const statusInicial = statusDoMvp.includes(statusPagamento)
    ? statusPagamento
    : "";
  const [status, setStatus] = useState(statusInicial);
  const [motivo, setMotivo] = useState(motivoIsencao ?? "");

  return (
    <form action={atualizarStatusPagamento} className="mt-3 space-y-3 border-t pt-3">
      <input type="hidden" name="evento_id" value={eventoId} />
      <input type="hidden" name="dupla_id" value={duplaId} />

      <label className="block space-y-1">
        <span className="text-sm font-medium">Atualizar pagamento</span>
        <select
          name="status_pagamento"
          value={status}
          onChange={(event) => setStatus(event.target.value)}
          required
          className="w-full rounded-md border px-3 py-2"
        >
          <option value="">
            {statusPagamento === "cancelado"
              ? "Cancelado: escolha um status para alterar"
              : "Selecione um status"}
          </option>
          <option value="pendente">Pendente</option>
          <option value="pago">Pago</option>
          <option value="isento">Isento</option>
        </select>
      </label>

      {status === "isento" && (
        <label className="block space-y-1">
          <span className="text-sm font-medium">Motivo da isenção</span>
          <input
            name="motivo_isencao"
            value={motivo}
            onChange={(event) => setMotivo(event.target.value)}
            required
            className="w-full rounded-md border px-3 py-2"
            placeholder="Informe o motivo"
          />
        </label>
      )}

      <button
        type="submit"
        className="rounded-md border px-3 py-2 text-sm font-medium"
      >
        Salvar pagamento
      </button>
    </form>
  );
}