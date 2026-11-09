# RussianWords Translation Gateway

This Cloudflare Worker implements the HTTPS contract expected by the RussianWords iOS app.

## Endpoint

After deployment:

- Health check: `GET https://<worker>.workers.dev/health`
- Translation: `POST https://<worker>.workers.dev/translate`

Request:

```json
{
  "text": "请问图书馆在哪里？",
  "sourceLanguage": "zh",
  "targetLanguage": "ru",
  "style": "polite"
}
```

Response:

```json
{
  "translation": "Подскажите, пожалуйста, где находится библиотека?",
  "explanation": null
}
```

## Provider

The Worker uses Cloudflare Workers AI through the `AI` binding with:

`@cf/zai-org/glm-4.7-flash`

No vendor API key is embedded in the iPhone app or this repository.

## Deploy

Requirements:

- A Cloudflare account
- Node.js / npm

Commands:

```bash
cd Backend/translation-worker
npm install
npx wrangler login
npm run deploy
```

Wrangler prints the deployed `workers.dev` URL. In RussianWords, open:

`翻译 → 设置`

and save the full endpoint:

`https://<your-worker>.workers.dev/translate`

Do not save only the domain; the iOS app does not append `/translate` automatically.

## Test

Health:

```bash
curl https://<your-worker>.workers.dev/health
```

Chinese → Russian:

```bash
curl -X POST https://<your-worker>.workers.dev/translate \
  -H 'Content-Type: application/json' \
  -d '{"text":"你好，请问附近有药店吗？","sourceLanguage":"zh","targetLanguage":"ru","style":"polite"}'
```

Russian → Chinese:

```bash
curl -X POST https://<your-worker>.workers.dev/translate \
  -H 'Content-Type: application/json' \
  -d '{"text":"Подскажите, пожалуйста, где находится ближайшая аптека?","sourceLanguage":"ru","targetLanguage":"zh","style":"natural"}'
```

## Notes

The public Worker currently has no user authentication because the present iOS client contract sends no authentication credential. This is appropriate for personal testing, but before public App Store distribution add authentication and rate limiting so other users cannot consume your quota.
