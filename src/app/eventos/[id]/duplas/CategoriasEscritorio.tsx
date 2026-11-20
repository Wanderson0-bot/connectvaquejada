import Link from "next/link";
import { ConfirmForm } from "@/components/ConfirmForm";
import {
  adicionarCategoriaNoEscritorio,
  editarCategoriaNoEscritorio,
  excluirCategoriaNoEscritorio,
  ocultarCategoriaNoEscritorio,
  reativarCategoriaNoEscritorio,
} from "./actions";

type Categoria = { id: string; nome: string; ordem: number; valor_inscricao: number; ativa: boolean };
const mensagensErro: Record<string, string> = {
  categoria: "Não foi possível salvar as alterações. Confira os dados e tente novamente.",
  "categoria-em-uso": "Esta categoria possui inscrições ou dados relacionados. Ela não foi excluída; oculte-a para preservar o histórico.",
};
const mensagensSucesso: Record<string, string> = {
  "categoria-oculta": "Categoria ocultada para novas inscrições; o histórico foi preservado.",
  "categoria-editada": "Categoria atualizada.",
  "categoria-reativada": "Categoria reativada para novas inscrições.",
  "categoria-excluida": "Categoria excluída.",
};

export function CategoriasEscritorio({ eventoId, categorias, aberto, erro, sucesso }: { eventoId: string; categorias: Categoria[]; aberto: boolean; erro?: string; sucesso?: string }) {
  return <>
    <Link href={`/eventos/${eventoId}/duplas?categoria=novo`} className="inline-flex items-center rounded-md border border-[#87320a] px-3 py-2 text-xs font-bold text-[#87320a] hover:bg-orange-50">Gerenciar categorias</Link>
    {aberto && <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4">
      <section role="dialog" aria-modal="true" aria-labelledby="categorias-title" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl">
        <header className="flex items-start justify-between gap-3"><div><h2 id="categorias-title" className="text-xl font-bold">Categorias da operação</h2><p className="mt-1 text-sm text-gray-600">Edite, oculte ou exclua categorias. O nome alterado também será exibido no histórico; categorias com dados relacionados não podem ser excluídas.</p></div><Link href={`/eventos/${eventoId}/duplas`} aria-label="Fechar" className="rounded p-1 text-xl">×</Link></header>
        {erro && <p role="alert" className="mt-4 rounded bg-red-50 p-3 text-sm text-red-800">{mensagensErro[erro] ?? mensagensErro.categoria}</p>}
        {sucesso && mensagensSucesso[sucesso] && <p role="status" className="mt-4 rounded bg-emerald-50 p-3 text-sm text-emerald-800">{mensagensSucesso[sucesso]}</p>}
        <form action={adicionarCategoriaNoEscritorio} className="mt-5 grid grid-cols-1 gap-3 rounded-xl border p-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          <input type="hidden" name="evento_id" value={eventoId}/>
          <label className="col-span-full grid min-w-0 gap-1 text-xs font-semibold">Nome da categoria<input name="nome" required maxLength={100} className="box-border w-full min-w-0 rounded-md border px-3 py-2 text-sm font-normal" placeholder="Ex.: Amador"/></label>
          <label className="grid min-w-0 gap-1 text-xs font-semibold">Ordem<input name="ordem" type="number" min="0" step="1" defaultValue="0" required className="box-border w-full min-w-0 rounded-md border px-3 py-2 text-sm font-normal"/></label>
          <label className="grid min-w-0 gap-1 text-xs font-semibold">Valor da inscrição (R$)<input name="valor_inscricao" type="number" min="0" step="0.01" defaultValue="0" required className="box-border w-full min-w-0 rounded-md border px-3 py-2 text-sm font-normal"/></label>
          <button className="col-span-full rounded-md bg-[#ff7a00] px-4 py-2 text-sm font-bold text-white">Adicionar categoria</button>
        </form>
        <ul className="mt-5 divide-y rounded-xl border">{categorias.map((categoria) => <li key={categoria.id} className="flex flex-col gap-3 p-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <p className="break-words font-semibold">{categoria.nome}{!categoria.ativa && <span className="ml-2 text-xs font-normal text-gray-500">Oculta</span>}</p>
            <p className="text-xs text-gray-500">Ordem {categoria.ordem} · R$ {Number(categoria.valor_inscricao).toFixed(2)}</p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <details className="relative">
              <summary className="cursor-pointer rounded-md border px-3 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50">Editar</summary>
              <form action={editarCategoriaNoEscritorio} className="absolute right-0 z-10 mt-2 grid w-64 gap-3 rounded-xl border bg-white p-4 shadow-xl">
                <input type="hidden" name="evento_id" value={eventoId}/>
                <input type="hidden" name="categoria_id" value={categoria.id}/>
                <label className="grid gap-1 text-xs font-semibold">Nome<input name="nome" required maxLength={100} defaultValue={categoria.nome} className="rounded-md border px-3 py-2 text-sm font-normal"/></label>
                <label className="grid gap-1 text-xs font-semibold">Ordem<input name="ordem" type="number" min="0" step="1" required defaultValue={categoria.ordem} className="rounded-md border px-3 py-2 text-sm font-normal"/></label>
                <label className="grid gap-1 text-xs font-semibold">Valor da inscrição (R$)<input name="valor_inscricao" type="number" min="0" step="0.01" required defaultValue={Number(categoria.valor_inscricao).toFixed(2)} className="rounded-md border px-3 py-2 text-sm font-normal"/></label>
                <button className="rounded-md bg-[#ff7a00] px-3 py-2 text-xs font-bold text-white">Salvar alterações</button>
              </form>
            </details>
            {categoria.ativa
              ? <form action={ocultarCategoriaNoEscritorio}>
                  <input type="hidden" name="evento_id" value={eventoId}/>
                  <input type="hidden" name="categoria_id" value={categoria.id}/>
                  <button className="rounded-md border px-3 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50">Ocultar</button>
                </form>
              : <form action={reativarCategoriaNoEscritorio}>
                  <input type="hidden" name="evento_id" value={eventoId}/>
                  <input type="hidden" name="categoria_id" value={categoria.id}/>
                  <button className="rounded-md border px-3 py-1.5 text-xs font-semibold text-emerald-800 hover:bg-emerald-50">Reativar</button>
                </form>}
            <ConfirmForm action={excluirCategoriaNoEscritorio} message={`Excluir a categoria "${categoria.nome}"? Ela só será removida se não tiver inscrições nem dados relacionados.`} className="inline-flex">
              <input type="hidden" name="evento_id" value={eventoId}/>
              <input type="hidden" name="categoria_id" value={categoria.id}/>
              <button className="rounded-md border border-red-200 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-50">Excluir</button>
            </ConfirmForm>
          </div>
        </li>)}</ul>
      </section>
    </div>}
  </>;
}
