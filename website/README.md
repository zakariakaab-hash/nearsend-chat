# Nearsend Chat website (chat.nearsend.app)

Plain HTML and CSS, no build step. `website/chat/` is the whole site.

- `index.html`, `styles.css`: home page, written by hand.
- `privacy/`, `support/`: built from `docs/nearsend-chat/PRIVACY.md` and `SUPPORT.md` by
  `python3 scripts/build_chat_web_pages.py`. Edit the Markdown, then rebuild.
- `images/`: the 6.3-inch App Store screenshots, resized
  (`sips -Z 1300 -s format jpeg -s formatOptions 80`).
- `og.png`: share image, drawn by `swift scripts/draw_chat_site_og.swift`.
- `favicon.svg`: the app icon (Bubble arrow), same geometry as `scripts/draw_ios_icon_variants.swift`.
- `fonts/Anton-Regular.ttf`: SIL Open Font License, see `fonts/OFL.txt`.
- `_headers`: security and cache headers for Cloudflare Pages.

Deploy: Cloudflare dashboard → Workers & Pages → nearsend-chat → Create deployment → upload a zip of the
contents of `website/chat/` (the files themselves at the top level of the zip, not the folder).
