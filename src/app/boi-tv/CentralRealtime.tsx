"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

export function CentralRealtime({ eventId }: { eventId: string }) {
  const router = useRouter();
  const [connected, setConnected] = useState(false);
  const [soundEnabled, setSoundEnabled] = useState(false);
  const [notice, setNotice] = useState("");
  const connectedRef = useRef(false);
  const soundEnabledRef = useRef(soundEnabled);
  const audioContextRef = useRef<AudioContext | null>(null);

  useEffect(() => { soundEnabledRef.current = soundEnabled; }, [soundEnabled]);

  useEffect(() => {
    const source = new EventSource(`/api/boi-tv/${eventId}/events`);
    source.onopen = () => {
      connectedRef.current = true;
      setConnected(true);
      router.refresh();
    };
    source.onmessage = (message) => {
      let payload: { eventType?: string } = {};
      try { payload = JSON.parse(message.data) as { eventType?: string }; } catch { /* Ignore malformed keepalive messages. */ }
      if (payload.eventType === "INSERT") {
        setNotice("Nova solicitação BOI TV recebida.");
        if (soundEnabledRef.current && audioContextRef.current) {
          const context = audioContextRef.current;
          const oscillator = context.createOscillator();
          const gain = context.createGain();
          oscillator.frequency.value = 880;
          gain.gain.value = 0.08;
          oscillator.connect(gain); gain.connect(context.destination);
          oscillator.start(); oscillator.stop(context.currentTime + 0.18);
        }
      }
      router.refresh();
    };
    source.onerror = () => {
      connectedRef.current = false;
      setConnected(false);
    };

    const fallback = window.setInterval(() => {
      if (!connectedRef.current) router.refresh();
    }, 10000);
    const onFocus = () => { if (document.visibilityState === "visible") router.refresh(); };
    document.addEventListener("visibilitychange", onFocus);
    return () => {
      window.clearInterval(fallback);
      document.removeEventListener("visibilitychange", onFocus);
      connectedRef.current = false;
      if (audioContextRef.current) void audioContextRef.current.close();
      source.close();
    };
  }, [eventId, router]);

  return <div className="mt-4 flex flex-wrap items-center gap-3 rounded-lg border bg-white p-3 text-sm">
    <span role="status" className={connected ? "text-emerald-800" : "text-amber-800"}>{connected ? "Central em tempo real" : "Reconectando · recuperação automática ativa"}</span>
    <button type="button" onClick={() => {
      if (!soundEnabled && typeof window !== "undefined" && window.AudioContext) {
        audioContextRef.current = new window.AudioContext();
        void audioContextRef.current.resume();
      }
      if (soundEnabled && audioContextRef.current) {
        void audioContextRef.current.close();
        audioContextRef.current = null;
      }
      setSoundEnabled((enabled) => !enabled);
    }} className="rounded border px-3 py-1.5 font-semibold">
      {soundEnabled ? "Som ativado" : "Ativar som"}
    </button>
    <span aria-live="polite" className="font-semibold text-amber-900">{notice}</span>
  </div>;
}
