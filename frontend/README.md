# Eureka Frontend (Phase D)

Vite + React 18 + TypeScript strict + Tailwind 3.

See `../../docs/rebuild/phase-d-frontend-design.md` for the spec.

## Dev

```bash
# from this folder (frontend/)
npm install
npm run dev            # Vite dev server on http://localhost:5173
                       # /api/* is proxied to http://localhost:8000
```

Backend (FastAPI) must be running separately:

```bash
# from project root
docker compose up backend
```

## Build / type-check

```bash
npm run build          # tsc -b && vite build → dist/
npm run lint           # ESLint
npm run test           # Vitest (only unit tests on pure lib/ helpers)
```

## Structure (see spec §二)

```
src/
├── components/      shell / skill / chat / calendar / library / notification / asset / ui
├── pages/           ChatPage / CalendarPage / LibraryPage / NotificationPage
├── hooks/           useChat / useFlashCapture / useSkillRegistry / …
├── lib/             api / sse / render-spec / format / types
├── context/         PresentationMode / Toast / Drawer
└── styles/          tokens.css (copy of docs/rebuild/design-tokens.css) + globals.css
```

## Design tokens

`src/styles/tokens.css` is the source of truth — anything in components should
reference Tailwind utilities that resolve to these vars
(e.g. `bg-eu-surface`, `text-eu-text-hi`, `rounded-eu-md`). New tokens go in
that file, then map into `tailwind.config.ts`'s `theme.extend`.
