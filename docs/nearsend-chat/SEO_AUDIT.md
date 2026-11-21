# nearsend.app SEO audit (for Nearsend Chat)

Checked 21 Nov 2026 from outside: the live HTML of the homepage, `/airdrop-alternative`, `/sv`, one blog post,
`robots.txt`, `sitemap.xml` and the response headers. The website's source code is not in this repo, so nothing here was changed.
Not measured: Core Web Vitals, Search Console data, backlinks, rankings.

## What is already good
- Every one of the 126 sitemap URLs returns 200. `www` and `http` redirect (301) to `https://nearsend.app/`.
- Unique title, meta description, canonical and a single H1 on every page checked. Open Graph and Twitter cards with a 1200×630 image.
- JSON-LD on every page (WebSite, Organization, WebApplication with a free Offer; BlogPosting + BreadcrumbList on posts).
- Homepage in 19 languages with `hreflang` and `x-default`; the Swedish page has its own `lang`, title and canonical.
- `robots.txt` allows search engines and AI assistants and points to the sitemap. Small HTML (about 14 KB), served via Cloudflare, HSTS on.

## Problems, most important first

1. **Nearsend Chat does not exist on the site.** No page, no link, the word "chat" never appears on the homepage, and
   `/chat` returns 404. Nobody can find the app through Google, and App Store Connect has no product URL to point to.
   **Fix:** a `/chat` page: H1 like "Chat with people nearby, with no signal", what it does, the App Store badge (once live),
   the honest limits (early version, not audited, SOS does not call emergency services), and FAQ. Add it to the sitemap,
   link it from the homepage and footer, and give it `MobileApplication` JSON-LD (`operatingSystem: iOS`,
   `applicationCategory: SocialNetworkingApplication`, free offer).
2. **No privacy policy for the app.** `/privacy` covers the file-transfer site only (it never mentions Bluetooth or
   Nearsend Chat), and `/chat/privacy` is 404. Apple requires a privacy policy URL. **Fix:** publish
   `docs/nearsend-chat/PRIVACY.md` at `/chat/privacy` and fill in the contact line (`support@nearsend.app` is already the
   address on `/contact`).
3. **No support page for the app.** App Store Connect asks for a support URL. `/contact` works for now; a `/chat/support`
   (or a section on `/chat`) explaining Report, Block and the support email is better.
4. **Once the app is live:** add `<meta name="apple-itunes-app" content="app-id=…">` to `/chat` so Safari on iPhone shows the
   install banner, and link the App Store listing back to `/chat` (it is the only place the listing can link out).
5. **Minor:** the sitemap's `<lastmod>` values look bulk-set (82 of 126 are 7 or 8 Oct 2026). Search engines ignore
   `lastmod` that does not track real edits; set it from each page's actual change date. Landing pages and posts
   have no `hreflang` (fine while they are English only).

## Keyword angle for the chat page
Search demand for this app is "offline messaging" and "Bluetooth chat" shaped, not "file transfer". Target phrases:
offline messenger, Bluetooth chat app, chat without internet, mesh messaging, festival / hiking / camping chat,
walkie-talkie app. Keep the same words as the App Store keyword field in `STORE_LISTING.md`, so the site and the listing
reinforce each other.
