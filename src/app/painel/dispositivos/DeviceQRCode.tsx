"use client";

import { useSyncExternalStore } from "react";
import { QRCodeSVG } from "qrcode.react";

const subscribe = () => () => {};
const getOrigin = () => window.location.origin;
const getServerOrigin = () => null;

const localHosts = new Set(["localhost", "127.0.0.1", "[::1]", "0.0.0.0"]);

export function DeviceQRCode({ code, activationOrigin }: { code: string; activationOrigin?: string }) {
  const origin = useSyncExternalStore(subscribe, getOrigin, getServerOrigin);

  if (!origin) return <div className="size-44 animate-pulse rounded-lg bg-orange-100" aria-label="Preparando QR code" />;

  const isLocal = localHosts.has(new URL(origin).hostname);
  const remoteOrigin = activationOrigin ?? (!isLocal && new URL(origin).protocol === "https:" ? origin : undefined);
  if (!remoteOrigin) {
    return <p className="max-w-56 p-2 text-sm text-stone-700">Configure o endereço HTTPS da versão web para que o celular possa abrir a ativação.</p>;
  }

  const activationUrl = new URL("/ativar", remoteOrigin);
  activationUrl.hash = new URLSearchParams({ codigo: code }).toString();
  const href = activationUrl.toString();

  return (
    <div className="grid justify-items-center gap-2">
      <QRCodeSVG value={href} size={208} level="M" marginSize={4} title="QR code para autorizar dispositivo" />
      <a href={href} className="text-sm font-medium text-orange-900 underline">Abrir link de ativação</a>
      <span className="text-xs text-stone-600">{activationUrl.host}</span>
    </div>
  );
}
