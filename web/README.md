# web

React SPA, built with Vite and served by nginx.

nginx proxies `/api` to the api Service, so no API address is baked into the
bundle and there is no CORS to configure — the same image runs anywhere.

Caching is split deliberately: `/assets/*` is immutable for a year because the
filenames are content-hashed, while `index.html` is never cached because it is
the file that names those hashes. A stale `index.html` points the browser at a
build that no longer exists, which is the "a hard refresh fixes it" bug.

```
npm run dev      vite, proxying /api to localhost:3000
npm run build    dist/
```
