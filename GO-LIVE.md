# Go-Live Runbook — turn this template into a real client's site

The template is a fully-working demo (Perth electrician placeholder). Everything
below is the *mechanical* work to rebrand it and switch on the lead-generating
bits. Budget an afternoon. Work top to bottom.

> Fill the [`client-intake-brief.md`](../client-intake-brief.md) with the owner
> first — every placeholder below maps to an answer in that brief.

---

## 1. Find-and-replace the placeholders

These exact strings appear across `index.html`, `services.html`, `about.html`,
`contact.html` (and a couple in the SEO files). Do a project-wide replace of
each. **Do the domain one first** — it's in the most places.

| Placeholder (search for)                     | Replace with                          | Where |
| -------------------------------------------- | ------------------------------------- | ----- |
| `https://www.ironbarkelectrical.com.au`      | the real domain (keep `https://www.`) | all `<head>`s, `sitemap.xml`, `robots.txt`, JSON-LD |
| `Ironbark Electrical` / `Ironbark`           | business name                         | everywhere (headers, footers, titles, OG) |
| `0400 000 000`                               | display phone                         | headers/footers, contact cards, call bar text |
| `tel:0400000000`                             | phone, digits only, no spaces         | every `tel:` link + call bar + JSON-LD `+61...` |
| `hello@ironbarkelectrical.com.au`            | enquiry email                         | contact page, footers, JSON-LD |
| `EC 00000`                                   | real WA licence (e.g. `EC 013245`)    | footers, about page |
| `ABN 00 000 000 000`                         | real ABN                              | footer bottom bar (all pages) |
| `Balcatta` + the northern-suburb list        | their base + real service suburbs     | about page, contact card, JSON-LD `areaServed` |
| `Family-owned ... since 2010` / `15+ years`  | real story + numbers                  | about page, hero, stats |

Then rewrite the **body copy** to be true (services offered, story, testimonials).
Structure stays; words change. Delete any service they don't offer.

## 2. Colours, logo, fonts (optional but high-impact)

- **Colours:** edit the `:root` block at the top of `css/styles.css`
  (`--c-brand`, `--c-accent`, …). The whole site + favicon follow.
- **Logo:** the inline `<svg>` bolt in each header/footer, plus `favicon.svg`.
  Swap the path, or replace with an `<img>`. If you change `--c-brand`/`--c-accent`,
  update the two hex values in `favicon.svg` too (it's a tiny standalone file).
- **Fonts:** the Google Fonts `<link>` in each `<head>` + `--font-body` in CSS.

## 3. Switch the contact form ON (do NOT skip)

Out of the box the form shows a success message but emails nobody (it's in
"demo mode" and logs a console warning). To make it actually send:

1. Sign up at <https://formspree.io> (free tier is fine), create a form, copy
   the endpoint — looks like `https://formspree.io/f/abcdwxyz`.
2. In `contact.html`, replace `YOUR_FORM_ID` in the `<form action="...">` with
   the real ID. That's the only change — `js/main.js` auto-detects a real
   endpoint and starts POSTing for real (with inline success/error handling).
3. Test: submit the live form, confirm the email arrives, check the owner's
   spam folder once and whitelist.

The hidden `_gotcha` honeypot and `_subject` fields are already in place.

## 4. Regenerate the share image + favicon

- The link-preview card is `og-image.png` (1200×630). To rebrand it, edit the
  colours/text in the generator script (`make_og.py` in the build scratchpad)
  and re-run, or just make your own 1200×630 PNG with the business name.
- `favicon.svg` is the browser-tab icon — see logo note above.

## 5. Local SEO — the part that actually gets him found

1. **Google Business Profile** is job #1 for a local trade — more important than
   the website for "electrician near me". Create/claim it at
   <https://business.google.com>, add the same phone/hours/area as the site,
   and put the website URL on it. Ask the owner for 3–5 customers to leave
   reviews in the first fortnight.
2. In `index.html`, the JSON-LD `Electrician` block: confirm every field is
   real. **Delete the `aggregateRating` block unless the reviews are genuine
   and shown on the page** — fake ratings get sites penalised.
3. Submit `sitemap.xml` in [Google Search Console](https://search.google.com/search-console)
   once the domain is live.

## 6. Deploy (free hosting)

Static site — any of these serve it as-is:

- **GitHub Pages** — push the folder to a repo, Settings → Pages → deploy from
  `main`. (This is the flow already used for the Arcfield template.)
- **Netlify / Cloudflare Pages** — drag-and-drop the folder in their dashboard.

Point the client's domain (~$15–20/yr at a `.com.au` registrar) at the host.
`https://www.` + apex both resolving is ideal — set the `www` in the DNS and an
apex redirect.

## 7. Pre-flight checklist (before you send him the link)

- [ ] Every placeholder in §1 replaced (grep the folder for `ironbark`, `00000`,
      `YOUR_FORM_ID`, `0400 000 000` — should return nothing but real content)
- [ ] Contact form sends a real email (test submission received)
- [ ] Phone links dial the right number on a phone (tap the sticky call bar)
- [ ] `<title>` + meta description on all 4 pages read well in a Google preview
- [ ] Favicon shows in the browser tab
- [ ] Paste the URL into <https://www.opengraph.xyz> — preview card looks right
- [ ] Opened on an actual phone: sticky call bar visible, nothing overlaps
- [ ] Licence number + ABN are the client's real ones
