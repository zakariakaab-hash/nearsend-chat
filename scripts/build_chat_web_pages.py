#!/usr/bin/env python3
"""Builds the Nearsend Chat privacy and support web pages from the Markdown in docs/nearsend-chat/.

Output (published on GitHub Pages from the gh-pages branch; App Store Connect needs both URLs):
  docs/nearsend-chat/web/chat/privacy/index.html  ->  BASE/chat/privacy/
  docs/nearsend-chat/web/chat/support/index.html  ->  BASE/chat/support/
If the pages move to nearsend.app, change BASE and rebuild.

Run from the repo root:  python3 scripts/build_chat_web_pages.py
Handles only the Markdown these two files use: #/## headings, paragraphs, "- " lists, > quotes, **bold**, `code`, links.
"""
import html
import os
import re

BASE = "https://zakariakaab-hash.github.io/nearsend-chat"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs", "nearsend-chat")
PAGES = [("PRIVACY.md", "chat/privacy", "Nearsend Chat privacy policy"),
         ("SUPPORT.md", "chat/support", "Nearsend Chat support")]

CSS = """
:root{--bg:#f6f8fc;--card:#ffffff;--ink:#13223f;--muted:#4b5b78;--link:#1d4fb8;--line:#dbe3f0}
@media (prefers-color-scheme: dark){:root{--bg:#0b1428;--card:#111d36;--ink:#eef2fa;--muted:#a9b6cf;--link:#8cb4ff;--line:#22324f}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:40px 16px 64px}
.card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:28px 24px}
h1{font-size:30px;line-height:1.2;margin:0 0 16px}
h2{font-size:21px;margin:32px 0 8px}
p,li{color:var(--ink)}
ul{padding-left:22px}
li{margin:4px 0}
blockquote{margin:16px 0;padding:8px 16px;border-left:4px solid var(--line);color:var(--muted)}
code{font:15px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--bg);padding:1px 5px;border-radius:6px}
a{color:var(--link)}
.brand{display:flex;align-items:center;gap:12px;margin:0 0 20px;text-decoration:none;color:var(--ink);font-weight:700;font-size:19px}
.brand svg{width:44px;height:44px;border-radius:11px;flex:none}
footer{margin-top:24px;color:var(--muted);font-size:14px;text-align:center}
"""


def inline(text):
    t = html.escape(text, quote=False)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"_([^_]+)_", r"<em>\1</em>", t)
    t = re.sub(r"(https?://[^\s<)]+)", r'<a href="\1">\1</a>', t)
    t = re.sub(r"\b([\w.+-]+@[\w-]+\.[\w.]+)\b", r'<a href="mailto:\1">\1</a>', t)
    return t


def convert(md):
    out, para, items, quote = [], [], [], []

    def flush():
        if para: out.append("<p>" + inline(" ".join(para)) + "</p>"); para.clear()
        if items: out.append("<ul>" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</ul>"); items.clear()
        if quote: out.append("<blockquote><p>" + inline(" ".join(quote)) + "</p></blockquote>"); quote.clear()

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.startswith("<!--"):
            flush(); continue
        if line.startswith("# "):
            flush(); out.append("<h1>" + inline(line[2:]) + "</h1>")
        elif line.startswith("## "):
            flush(); out.append("<h2>" + inline(line[3:]) + "</h2>")
        elif line.startswith("- "):
            if para or quote: flush()
            items.append(line[2:])
        elif line.startswith("> "):
            if para or items: flush()
            quote.append(line[2:])
        elif items and raw.startswith("  "):
            items[-1] += " " + line.strip()
        else:
            if items or quote: flush()
            para.append(line.strip())
    flush()
    return "\n".join(out)


LOGO = ('<svg viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="14" fill="#2F7BF5"/>'
        '<path d="M18 16h28a6 6 0 0 1 6 6v16a6 6 0 0 1-6 6H30l-9 8v-8h-3a6 6 0 0 1-6-6V22a6 6 0 0 1 6-6z" '
        'fill="none" stroke="#fff" stroke-width="3.5" stroke-linejoin="round"/>'
        '<circle cx="24" cy="30" r="3" fill="#fff"/><path d="M31 30h11m-4-4 4 4-4 4" fill="none" stroke="#fff" '
        'stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>')

for src, path, title in PAGES:
    body = convert(open(os.path.join(DOCS, src), encoding="utf-8").read())
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(title)}: Nearsend Chat, offline chat with people nearby over Bluetooth.">
<link rel="canonical" href="{BASE}/{path}/">
<style>{CSS}</style>
</head>
<body>
<main>
<a class="brand" href="{BASE}/chat/support/" aria-label="Nearsend Chat">{LOGO}<span>Nearsend Chat</span></a>
<div class="card">
{body}
</div>
<footer><a href="{BASE}/chat/privacy/">Privacy</a> · <a href="{BASE}/chat/support/">Support</a> · <a href="https://nearsend.app/">nearsend.app</a></footer>
</main>
</body>
</html>
"""
    dest = os.path.join(DOCS, "web", path, "index.html")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w", encoding="utf-8").write(page)
    print("wrote", os.path.relpath(dest, ROOT))
