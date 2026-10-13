// Locks /admin behind a password (the ADMIN_TOKEN environment variable on Vercel). Signing in sets
// a cookie that lasts 400 days, the longest browsers keep one, and every visit renews it, so a
// browser that signed in once stays signed in. There is deliberately no sign-out.
// Without ADMIN_TOKEN the page stays locked.

export const config = {
  matcher: ["/admin", "/admin.html", "/admin/:path*"],
};

const COOKIE = "fokly_admin";
const MAX_AGE = 400 * 24 * 60 * 60;

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Compares hashes, so the time taken says nothing about how much of a guess was right.
async function same(a, b) {
  const [x, y] = await Promise.all([sha256("a:" + a), sha256("a:" + b)]);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

const cookie = (value) =>
  `${COOKIE}=${value}; Path=/admin; Max-Age=${MAX_AGE}; HttpOnly; Secure; SameSite=Lax`;

export default async function middleware(request) {
  const url = new URL(request.url);
  const token = process.env.ADMIN_TOKEN;
  if (!token) return new Response("Not available.", { status: 404 });
  const session = await sha256("fokly-admin:" + token);

  if (url.pathname === "/admin/login" && request.method === "POST") {
    const form = await request.formData().catch(() => null);
    const ok = form && (await same(String(form.get("password") || ""), token));
    return new Response(null, {
      status: 303,
      headers: ok
        ? { Location: "/admin", "Set-Cookie": cookie(session), "Cache-Control": "no-store" }
        : { Location: "/admin?wrong", "Cache-Control": "no-store" },
    });
  }

  const sent = (request.headers.get("cookie") || "").split(/;\s*/).find((c) => c.startsWith(COOKIE + "="));
  if (sent && (await same(sent.slice(COOKIE.length + 1), session))) {
    // Signed in: let the page through and push the cookie's expiry out again.
    return new Response(null, {
      headers: { "x-middleware-next": "1", "Set-Cookie": cookie(session), "Cache-Control": "private, no-store" },
    });
  }

  return new Response(loginPage(url.searchParams.has("wrong")), {
    status: 401,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" },
  });
}

function loginPage(wrong) {
  return `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Fokly Stats</title>
<link rel="icon" type="image/png" href="/favicon.png">
<style>
:root { --bg: #FCFAF9; --ink: #18120F; --soft: #6E625D; --line: rgba(24, 18, 15, 0.12); --card: #FFFFFF; --coral: #F45B44; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0F0B0A; --ink: #F6EFEC; --soft: #A69891; --line: rgba(246, 239, 236, 0.14); --card: #1A1514; --coral: #FA6652; color-scheme: dark; }
}
* { box-sizing: border-box; }
body {
  margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px; background: var(--bg); color: var(--ink);
  font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; -webkit-font-smoothing: antialiased;
}
form { width: 100%; max-width: 320px; text-align: center; }
img { width: 56px; height: 56px; border-radius: 13px; }
h1 { font: 650 19px/1.2 ui-rounded, "SF Pro Rounded", -apple-system, system-ui, sans-serif; letter-spacing: -0.02em; margin: 14px 0 22px; }
input {
  width: 100%; font: inherit; color: inherit; background: var(--card); border: 1px solid var(--line); border-radius: 12px;
  padding: 11px 14px; outline: none;
}
input:focus { border-color: var(--coral); box-shadow: 0 0 0 3px color-mix(in srgb, var(--coral) 22%, transparent); }
button {
  width: 100%; margin-top: 10px; font: 650 15px ui-rounded, "SF Pro Rounded", -apple-system, system-ui, sans-serif; color: #fff;
  background: var(--coral); border: 0; border-radius: 12px; padding: 11px; cursor: pointer;
}
button:focus-visible { outline: 2px solid var(--coral); outline-offset: 2px; }
p { color: var(--coral); font-size: 13px; margin: 12px 0 0; min-height: 1.45em; }
</style>
<form method="post" action="/admin/login">
  <img src="/apple-touch-icon.png" alt="">
  <h1>Fokly Stats</h1>
  <input type="hidden" name="username" value="admin" autocomplete="username">
  <input type="password" name="password" placeholder="Password" autocomplete="current-password" aria-label="Password" required autofocus>
  <button type="submit">Sign In</button>
  <p role="alert">${wrong ? "That's not it." : ""}</p>
</form>
</html>`;
}
