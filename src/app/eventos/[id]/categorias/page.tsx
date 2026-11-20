import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function CategoriasPage({ params }: Props) {
  const { id } = await params;
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

  const { data: categorias, error } = await supabase
    .from("categorias")
    .select("id, nome, ordem, valor_inscricao, ativa")
    .eq("evento_id", id)
    .order("ordem", { ascending: true });

  if (error) {
    return (
      <main className="mx-auto min-h-screen max-w-3xl p-8">
        <p role="alert" className="text-red-600">
          Não foi possível carregar as categorias.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen max-w-3xl p-8">
      <Link href="/painel" className="text-sm text-gray-600 underline">
        Voltar aos eventos
      </Link>

      <h1 className="mt-6 text-2xl font-semibold">Categorias</h1>
      <p className="mt-1 text-sm text-gray-600">Evento: {evento.nome}</p>

      <Link
        href={`/eventos/${id}/categorias/nova`}
        className="mt-5 inline-block rounded-md bg-black px-4 py-2 text-sm font-medium text-white"
      >
        Cadastrar categoria
      </Link>

      {!categorias || categorias.length === 0 ? (
        <p className="mt-6 rounded-lg border p-6 text-gray-600">
          Ainda não há categorias neste evento.
        </p>
      ) : (
        <ul className="mt-6 space-y-3">
          {categorias.map((categoria) => (
            <li key={categoria.id} className="rounded-lg border p-4">
              <h2 className="font-medium">{categoria.nome}{!categoria.ativa && <span className="ml-2 text-xs font-normal text-gray-500">Oculta para novas inscrições</span>}</h2>
              <p className="mt-1 text-sm text-gray-600">
                Ordem: {categoria.ordem} · Inscrição:{" "}
                {Number(categoria.valor_inscricao).toLocaleString("pt-BR", {
                  style: "currency",
                  currency: "BRL",
                })}
              </p>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
