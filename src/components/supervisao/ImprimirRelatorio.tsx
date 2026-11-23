"use client";

export function ImprimirRelatorio() {
  return <button type="button" className="operation-secondary" onClick={() => window.print()}>Imprimir / Salvar PDF</button>;
}
