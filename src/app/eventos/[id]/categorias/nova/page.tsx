import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { criarCategoria } from "./actions";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ erro?: string }>;
};

export default async function NovaCategoriaPage({
  params,
  searchParams,
}: Props) {
  const { id } = await params;
  const { erro } = await searchParams;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { data: evento } = await supabase
    .from("eventos")
    .select("id, nome")
    .eq("id", id)
    .single();

  if (!evento) {
    notFound();
  }

  const mensagemErro =
    erro === "campos"
      ? "Confira o nome, a ordem e o valor da inscrição."
      : erro === "cadastro"
        ? "Não foi possível cadastrar. Verifique se já existe uma categoria com esse nome no evento."
        : null;

  return (
    <main className="mx-auto min-h-screen max-w-2xl p-8">
      <Link href="/painel" className="text-sm text-gray-600 underline">
        Voltar aos eventos
      </Link>

      <h1 className="mt-6 text-2xl font-semibold">Nova categoria</h1>
      <p className="mt-1 text-sm text-gray-600">Evento: {evento.nome}</p>

      {mensagemErro && (
        <p role="alert" className="mt-5 rounded-md bg-red-50 p-3 text-sm text-red-700">
          {mensagemErro}
        </p>
      )}

      <form action={criarCategoria} className="mt-6 space-y-5">
        <input type="hidden" name="eventoId" value={evento.id} />

        <label className="block space-y-2">
          <span className="text-sm font-medium">Nome da categoria</span>
          <input
            name="nome"
            required
            maxLength={100}
            className="w-full rounded-md border px-3 py-2"
            placeholder="Ex.: Amador"
          />
        </label>

        <label className="block space-y-2">
          <span className="text-sm font-medium">Ordem</span>
          <input
            name="ordem"
            type="number"
            min="0"
            step="1"
            defaultValue="0"
            required
            className="w-full rounded-md border px-3 py-2"
          />
        </label>

        <label className="block space-y-2">
          <span className="text-sm font-medium">Valor da inscrição (R$)</span>
          <input
            name="valor_inscricao"
            type="number"
            min="0"
            step="0.01"
            defaultValue="0"
            required
            className="w-full rounded-md border px-3 py-2"
          />
        </label>

        <button
          type="submit"
          className="rounded-md bg-black px-4 py-2 font-medium text-white"
        >
          Cadastrar categoria
        </button>
      </form>
    </main>
  );
}