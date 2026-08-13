# RiasDxD — Landing site

A single, self-contained landing page for RiasDxD (`index.html`). All CSS, JS and
images are inlined, so it works from any device and can be hosted anywhere with no
build step.

## Preview

Open `index.html` directly in a browser, or serve the folder:

```bash
cd site && python3 -m http.server 8080   # then visit http://localhost:8080
```

## Deploy (any static host)

- **GitHub Pages** — point Pages at this folder, or copy `index.html` to a
  `docs/` folder / `gh-pages` branch root.
- **Netlify / Vercel / Cloudflare Pages** — drag-and-drop the `site/` folder, or
  set it as the publish directory. No build command needed.

## Placeholders to update

These point at sensible defaults — change them to your real links:

- **Download button / "Get the app"** → `https://github.com/harivignesh-96/RiasDxD/releases/latest`
- **Community / Telegram** → `https://t.me/sozoApp`
- **GitHub** → `https://github.com/harivignesh-96/RiasDxD`

The Bitcoin donation QR and address match the in-app donate screen
(`bc1q9je9tkj4789s9kvesmmcmh6h06lxga7u4efq2y`).

> Note: the screenshots are the app's existing marketing images and still show the
> old "Sozo" branding — regenerate them from the renamed build when convenient.
