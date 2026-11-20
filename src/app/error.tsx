"use client";

export default function ErroDaPagina({ retry }: { retry: () => void }) {
  return (
    <main className="mx-auto grid min-h-svh max-w-lg content-center gap-4 px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Não foi possível carregar a página</h1>
      <p className="text-stone-600">Tente novamente para continuar.</p>
      <button type="button" onClick={retry} className="operation-primary justify-self-start">Tentar novamente</button>
    </main>
  );
}
