#!/usr/bin/env python3
"""Builds the privacy and support pages of the Nearsend Chat website (website/chat/) from docs/nearsend-chat/*.md.

Output (deployed with the rest of website/chat/ to the Cloudflare Pages project "nearsend-chat"):
  website/chat/privacy/index.html  ->  https://chat.nearsend.app/privacy/
  website/chat/support/index.html  ->  https://chat.nearsend.app/support/
App Store Connect uses both URLs. The pages share website/chat/styles.css and the header and footer of index.html.

Run from the repo root:  python3 scripts/build_chat_web_pages.py
Handles only the Markdown these two files use: #/## headings, paragraphs, "- " lists, > quotes, **bold**, `code`, links.
"""
import html
import os
import re

BASE = "https://chat.nearsend.app"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs", "nearsend-chat")
SITE = os.path.join(ROOT, "website", "chat")
PAGES = [("PRIVACY.md", "privacy", "Privacy policy · Nearsend Chat", "How Nearsend Chat handles data: no accounts, no servers of our own, no tracking."),
         ("SUPPORT.md", "support", "Support · Nearsend Chat", "Help with Nearsend Chat: getting started, common questions and how to reach us.")]


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


HEADER = """<a class="skip" href="#main">Skip to content</a>
<header class="site-header">
  <div class="bar">
    <a class="brand" href="/"><img src="/icon-v2.svg" alt="" width="34" height="34"><span>Nearsend Chat</span></a>
    <nav class="nav" aria-label="Main">
      <a class="opt" href="/#how">How it works</a>
      <a class="opt" href="/privacy/">Privacy</a>
      <a href="/support/">Support</a>
    </nav>
  </div>
</header>"""

FOOTER = """<footer>
  <div class="wrap foot">
    <nav aria-label="Footer">
      <a href="/privacy/">Privacy</a>
      <a href="/support/">Support</a>
      <a href="mailto:support@nearsend.app">support@nearsend.app</a>
      <a href="https://github.com/zakariakaab-hash/nearsend-chat">Source code</a>
    </nav>
    <p>© 2026 Nearsend Chat</p>
  </div>
</footer>"""

for src, path, title, desc in PAGES:
    body = convert(open(os.path.join(DOCS, src), encoding="utf-8").read())
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<link rel="canonical" href="{BASE}/{path}/">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#356CB5">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#040B1F">
<meta name="color-scheme" content="light dark">
<link rel="icon" type="image/svg+xml" href="/icon-v2.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png?v=2">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:image" content="{BASE}/og.png">
<link rel="stylesheet" href="/styles.css">
</head>
<body>
{HEADER}
<main id="main" class="wrap doc">
<div class="card">
{body}
</div>
</main>
{FOOTER}
</body>
</html>
"""
    dest = os.path.join(SITE, path, "index.html")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w", encoding="utf-8").write(page)
    print("wrote", os.path.relpath(dest, ROOT))
