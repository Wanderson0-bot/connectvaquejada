import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function proxy(request: NextRequest) {
  const hasDeviceSession = request.cookies.getAll().some(({ name }) => name === "cv-device-auth" || name.startsWith("cv-device-auth."));
  const isMobileDevice = request.cookies.has("cv-mobile-device");
  if (hasDeviceSession) {
    const pathname = request.nextUrl.pathname;
    if (pathname !== "/ativar" && pathname !== "/api/dispositivos/ativar") {
      const eventId = request.cookies.get("cv-device-event")?.value;
      const screen = request.cookies.get("cv-device-screen")?.value;
      let destination = "/ativar";
      let allowed = false;
      if (eventId && /^[0-9a-f-]{36}$/i.test(eventId)) {
        const eventPath = `/eventos/${eventId}`;
        if (screen === "locutor") {
          destination = `${eventPath}/pista-ops`;
          allowed = pathname === destination || pathname === `${eventPath}/x1` || pathname === `${eventPath}/historico`;
        } else if (screen === "escritorio") {
          destination = `${eventPath}/duplas`;
          allowed = pathname === destination || pathname.startsWith(`${destination}/`) || pathname === `${eventPath}/historico`;
        } else if (screen === "boi_tv") {
          destination = `/boi-tv/${eventId}`;
          allowed = pathname === destination || pathname === "/boi-tv" || pathname === `/api${destination}/events`;
        }
      }
      if (!allowed) {
        return NextResponse.redirect(new URL(destination, request.url));
      }
    }
  }

  let response = NextResponse.next({ request });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      ...(hasDeviceSession ? {
        cookieOptions: {
          name: "cv-device-auth",
          httpOnly: true,
          secure: process.env.NODE_ENV === "production",
          sameSite: "lax" as const,
          path: "/",
        },
      } : {}),
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
          Object.entries(headers).forEach(([name, value]) => response.headers.set(name, value));
        },
      },
    }
  );

  const { data: credentials, error: claimsError } = await supabase.auth.getClaims();
  if (isMobileDevice && !["/ativar", "/api/dispositivos/ativar"].includes(request.nextUrl.pathname)) {
    const eventId = request.cookies.get("cv-device-event")?.value;
    const role = request.cookies.get("cv-device-screen")?.value;
    if (claimsError?.name === "AuthRetryableFetchError") {
      return NextResponse.json({ error: "Não foi possível verificar a sessão do dispositivo. Tente novamente." }, { status: 503 });
    }
    if (hasDeviceSession && credentials?.claims?.sub && eventId && role) {
      const { data: ativo, error } = await supabase.rpc("pista_ops_mobile_touch", {
        p_evento_id: eventId, p_funcao: role,
      });
      if (ativo) return response;
      if (error) return NextResponse.json({ error: "Não foi possível verificar a sessão do dispositivo. Tente novamente." }, { status: 503 });
    }
    const expired = NextResponse.redirect(new URL("/ativar?estado=sessao", request.url), 303);
    for (const { name } of request.cookies.getAll()) {
      if (name.startsWith("cv-device-") || name === "cv-mobile-device") expired.cookies.delete(name);
    }
    return expired;
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
