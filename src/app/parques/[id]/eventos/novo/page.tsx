import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { criarEventoDoParque } from "@/app/parques/actions";

export default async function NovoEventoParquePage({ params, searchParams }: PageProps<"/parques/[id]/eventos/novo">) {
  const { id } = await params;
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: parques } = await supabase.rpc("painel_listar_parques");
  const parque = (parques ?? []).find((item: { id: string }) => item.id === id);
  if (!parque) notFound();
  return <main className="mx-auto min-h-screen max-w-xl px-5 py-10">
    <Link href={`/parques/${id}`} className="text-sm text-gray-600 underline">Voltar ao parque</Link>
    <h1 className="mt-6 text-3xl font-bold">Novo evento</h1><p className="mt-2 text-gray-600">{parque.nome}</p>
    {query.erro === "formato" && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-800">Selecione um formato de competição válido.</p>}
    <form action={criarEventoDoParque} className="mt-7 grid gap-5 rounded-2xl bg-white p-6 shadow-lg">
      <input type="hidden" name="parque_id" value={id} />
      <label className="grid gap-2 text-sm font-semibold">Nome do evento<input name="nome" required maxLength={120} className="rounded-lg border px-3 py-2.5 font-normal" /></label>
      <label className="grid gap-2 text-sm font-semibold">Data<input name="data" type="date" required className="rounded-lg border px-3 py-2.5 font-normal" /></label>
      <label className="grid gap-2 text-sm font-semibold">Formato da competição
        <select name="formato_competicao" defaultValue="tradicional" className="rounded-lg border px-3 py-2.5 font-normal">
          <option value="tradicional">Tradicional · classificatória</option>
          <option value="tropa_de_elite">Tropa de Elite · eliminatória</option>
        </select>
      </label>
      <button className="rounded-lg bg-[#ff7a00] px-5 py-3 font-bold text-white">Criar evento</button>
    </form>
  </main>;
}
