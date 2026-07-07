# Business Website Template — "Ironbark Electrical"

A complete 4-page business website built with **plain HTML, CSS and JavaScript** —
no frameworks, no build tools, nothing to install. Open `index.html` in a browser
and it just works. This is the classic "brochure site" that small businesses pay
for: home page that sells, services page that details, about page that builds
trust, contact page that converts.

The demo business is a fictional Perth electrician, but the template is
designed to be rebranded for any local/service business in under an hour.

> **Rebranding a real client's site?** Follow [`GO-LIVE.md`](GO-LIVE.md) — it's
> the step-by-step runbook (find/replace table, turning the contact form on,
> local SEO, deploy). The list below is the quick overview.

## File structure

```
business-template/
├── index.html        Home — hero, services grid, stats, testimonials, CTA
├── services.html     Detailed service sections (alternating layout)
├── about.html        Story, values, service area
├── contact.html      Contact info cards + quote request form (Formspree)
├── css/
│   └── styles.css    ALL styling, shared by every page
├── js/
│   └── main.js       Mobile nav, scroll animations, form submit
├── favicon.svg       Browser-tab icon (bolt on brand navy)
├── og-image.png      1200×630 link-preview card (social shares)
├── sitemap.xml       For Google Search Console
├── robots.txt        Crawler rules + sitemap pointer
└── GO-LIVE.md        Rebrand + deploy runbook
```

## What's already wired for production

- **Working contact form** — POSTs to Formspree (no backend); demo-safe until
  you paste in a real endpoint. See §"contact form" below.
- **Sticky mobile call bar** — a "Call now / Get a quote" pair pinned to the
  bottom on phones (hidden on desktop). Biggest conversion lever for a trade.
- **Local SEO** — `Electrician` schema.org JSON-LD (hours, phone, service area,
  rating), Open Graph + Twitter cards, canonical tags, `sitemap.xml`,
  `robots.txt`, favicon and a generated share image.

## How the pieces fit together

- **Every page loads the same `styles.css` and `main.js`.** The header, footer
  and design language are identical across pages, so the site feels like one
  thing. (The header/footer HTML is copy-pasted into each page — that
  duplication is the #1 reason frameworks/static-site generators exist. Live
  with it at 4 pages; automate it at 40.)
- **`styles.css` starts with design tokens** (`:root` custom properties).
  Colours, fonts, spacing and shadows are defined once and referenced
  everywhere. This is the single most important idea in the file.
- **`main.js` is progressive enhancement** — the site works fine with JS
  disabled; JS just adds the mobile menu, scroll-reveal animations, the footer
  year, and form feedback.

## Rebranding checklist (turn this into a real client's site)

1. **Colours** — edit the first ~10 lines of `css/styles.css` (`--c-brand`,
   `--c-accent`, etc.). The whole site follows.
2. **Business name** — find-and-replace `Ironbark Electrical` across the four
   HTML files. Same for phone, email, ABN, licence number.
3. **Logo** — the inline `<svg>` lightning bolt in each header/footer; swap the
   path or replace with an `<img>`.
4. **Copy** — rewrite the text. Structure stays, words change.
5. **Fonts** — swap the Google Fonts `<link>` in each `<head>` and
   `--font-body` in the CSS.
6. **`<title>` and `<meta name="description">`** on each page — this is what
   Google shows in search results.

## Making the contact form actually send email

The form is already wired to [Formspree](https://formspree.io) (free tier is
fine) and submits via `fetch()` so the visitor stays on the page and sees an
inline success/error message. It just needs a real endpoint:

1. Sign up, create a form, copy your endpoint (`https://formspree.io/f/abcdwxyz`).
2. In `contact.html`, replace `YOUR_FORM_ID` in the `<form action="...">`.

That's it — `js/main.js` detects the placeholder and runs in "demo mode" (shows
success without sending, and logs a console warning) until a real ID is present,
then switches to real submissions automatically. No JS edit needed. Full steps
in [`GO-LIVE.md`](GO-LIVE.md).

## Hosting (free)

Any static host serves this as-is:

- **GitHub Pages** — push the folder to a repo, enable Pages in settings.
- **Netlify / Cloudflare Pages** — drag-and-drop the folder in their dashboard.

A custom domain (~$15/yr) points at any of them.

## Local preview

Double-clicking `index.html` works. For a proper local server (matches how
hosting behaves):

```powershell
python -m http.server 8000
# then open http://localhost:8000
```
