# HabitBloom Widget Worker

Cloudflare Workers + Durable Objects backend for HabitBloom widget snapshots.

This service stores only the current widget rendering snapshot for one `deviceKey`.
It does not store Apple ID, email, real names, precise location, or full habit history.

## API

- `GET /v1/snapshot/:deviceKey`
- `PUT /v1/snapshot/:deviceKey` with `Authorization: Bearer WRITE_TOKEN`
- `POST /v1/checkin/:deviceKey` with `Authorization: Bearer WRITE_TOKEN`
- `GET /v1/backup/:deviceKey` with `Authorization: Bearer WRITE_TOKEN`
- `PUT /v1/backup/:deviceKey` with `Authorization: Bearer WRITE_TOKEN`

## Local Setup

```sh
cp .dev.vars.example .dev.vars
npm install
npm run dev
```

## Deploy

```sh
npx wrangler login
npm run deploy
```

After deployment, configure the app with the Xcode build settings documented in `../../REMOTE_SYNC.md`.
