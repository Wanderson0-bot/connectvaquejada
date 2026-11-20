"use client";

import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, X } from "lucide-react";
import { criarParqueNoModal, type CadastroParqueState } from "@/app/parques/actions";

const estadoInicial: CadastroParqueState = {};

export function NovoParqueModal() {
  const [aberto, setAberto] = useState(false);
  const [mensagemSucesso, setMensagemSucesso] = useState("");
  const router = useRouter();

  const [estado, action, pendente] = useActionState(async (anterior: CadastroParqueState, dados: FormData) => {
    const resultado = await criarParqueNoModal(anterior, dados);
    if (resultado.parqueId) {
      setAberto(false);
      setMensagemSucesso("Parque cadastrado.");
      router.refresh();
    }
    return resultado;
  }, estadoInicial);

  function abrir() {
    setMensagemSucesso("");
    setAberto(true);
  }

  return <>
    <button type="button" onClick={abrir} aria-label="Cadastrar parque" title="Cadastrar parque" className="dashboard-add-button"><Plus className="size-6" /></button>
    {mensagemSucesso && <p role="status" className="sr-only">{mensagemSucesso}</p>}
    {aberto && <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget && !pendente) setAberto(false); }}>
      <section role="dialog" aria-modal="true" aria-labelledby="novo-parque-titulo" className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl sm:p-7">
        <header className="flex items-start justify-between gap-4">
          <div><h2 id="novo-parque-titulo" className="text-2xl font-bold">Cadastrar parque</h2><p className="mt-1 text-sm text-gray-600">Informe o nome e a localização do parque.</p></div>
          <button type="button" onClick={() => setAberto(false)} disabled={pendente} aria-label="Fechar" className="rounded-md p-1 text-gray-500 hover:bg-gray-100 disabled:opacity-50"><X className="size-5" /></button>
        </header>
        {estado.erro && <p role="alert" className="mt-5 rounded-lg bg-red-50 p-3 text-sm text-red-800">{estado.erro}</p>}
        <form action={action} className="mt-6 grid gap-5">
          <label className="grid gap-2 text-sm font-semibold">Nome do parque<input name="nome" required maxLength={120} autoFocus className="rounded-lg border px-3 py-2.5 font-normal outline-none focus:ring-2 focus:ring-orange-500" placeholder="Ex.: Rancho do Vaqueiro" /></label>
          <label className="grid gap-2 text-sm font-semibold">Localização<input name="localizacao" required maxLength={180} className="rounded-lg border px-3 py-2.5 font-normal outline-none focus:ring-2 focus:ring-orange-500" placeholder="Cidade, Estado" /></label>
          <div className="flex justify-end gap-3">
            <button type="button" onClick={() => setAberto(false)} disabled={pendente} className="rounded-lg border px-5 py-2.5 font-semibold text-gray-700 disabled:opacity-50">Cancelar</button>
            <button type="submit" disabled={pendente} className="rounded-lg bg-[#ff7a00] px-5 py-2.5 font-bold text-white disabled:opacity-60">{pendente ? "Cadastrando..." : "Cadastrar parque"}</button>
          </div>
        </form>
      </section>
    </div>}
  </>;
}
