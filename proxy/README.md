# CampOn AI Proxy (Azure Functions)

Stateless proxy for the CampOn AI camping planner. It takes the app's request
(natural-language query + onboarding context + candidate campsites), fetches
camping weather from Open-Meteo, asks Google Gemini 3.6 Flash for a structured
plan, and returns it. When `GEMINI_API_KEY` is unset or the model fails, it
returns a deterministic fallback plan so the app never breaks.

It also serves the night preview: given the numbers the app already computed
(cloud, wind, night low, moon), Gemini writes a short first-person scene of that
night at that campsite. The same fallback rule applies — no key, no problem.

- Runtime: Azure Functions v4 (Node 20+), HTTP trigger, anonymous.
- Endpoints: `POST /api/plan`, `POST /api/preview`,
  `GET /api/campsite-image?name=...&region=...`,
  `GET /api/campsite-reservation?name=...`
- LLM: Google Gemini 3.6 Flash. Free-tier keys remain free within their quota;
  paid-tier keys are billed by input, output, and thinking tokens. The key is
  stored in the app setting `GEMINI_API_KEY`.
- Weather: Open-Meteo (free, keyless). `/api/preview` does not call it — the app
  sends its own numbers so the scene never contradicts the card the user saw.
- Campsite images: NAVER API HUB image search. It is called only when the app's
  campsite response has no image and caches results in memory for 24 hours.
- Campsite reservations: NAVER API HUB local search. It is called only when the
  campsite response has no reservation URL and caches results for 24 hours.

## Local

```sh
npm install
npm test          # node --test (weather, plan core, handler smoke)
npm run build     # esbuild -> dist/plan.js
```

## Deploy (Azure CLI, no func required)

Requires `az login` first (Azure for Students subscription is fine).

```sh
# 1. one-time resources (names must be globally unique)
RG=campon-rg
LOC=koreacentral
STORAGE=camponaistore$RANDOM
APP=campon-ai-proxy            # -> https://campon-ai-proxy.azurewebsites.net

az group create -n $RG -l $LOC
az storage account create -n $STORAGE -g $RG -l $LOC --sku Standard_LRS
az functionapp create -n $APP -g $RG -s $STORAGE \
  --consumption-plan-location $LOC --runtime node --runtime-version 20 \
  --functions-version 4 --os-type Linux

# 2. app settings
az functionapp config appsettings set -n $APP -g $RG \
  --settings GEMINI_API_KEY=<your_gemini_key> \
    NAVER_API_HUB_CLIENT_ID=<your_client_id> \
    NAVER_API_HUB_CLIENT_SECRET=<your_client_secret>

# 3. build + zip deploy
npm run build
STAGE=$(mktemp -d)
cp -r host.json package.json dist "$STAGE"/
( cd "$STAGE" && npm install --omit=dev --silent )
( cd "$STAGE" && zip -qr deploy.zip . )
az functionapp deployment source config-zip -n $APP -g $RG --src "$STAGE/deploy.zip"
```

## Verify

```sh
curl -s -X POST https://$APP.azurewebsites.net/api/plan \
  -H 'content-type: application/json' \
  -d '{"query":"주말 2명 강원 초보 오토캠핑","context":{"date":"2026-08-01","people":2,"hasCar":true,"experience":"초보","region":"강원","preferences":[],"equipment":[]},"coords":{"lat":37.8,"lon":128.9},"candidates":[{"name":"가리왕산 캠핑장","facility":["전기"],"equipmentRental":[]}]}'
```

Expect `"source":"llm"` with a Korean plan (or `"fallback"` if the key is unset).

```sh
curl -s -X POST https://$APP.azurewebsites.net/api/preview \
  -H 'content-type: application/json' \
  -d '{"place":"가리왕산 캠핑장","date":"2026-08-15","people":2,"experience":"초보","weather":{"cloudPct":4,"precipPct":0,"windMs":1.2,"nightLowC":14,"myTempC":30},"sky":{"moonIlluminationPct":4,"moonInterferencePct":3,"score":91,"grade":"milkyWay"}}'
```

Expect a `preview` with a title, five `lines`, and a `closing`.

## Point the app at the deployment

```sh
flutter run --dart-define=PLAN_PROXY_URL=https://$APP.azurewebsites.net
```

For campsite image fallback, point `IMAGE_PROXY_URL` at the same deployment:

```sh
flutter run \
  --dart-define=PLAN_PROXY_URL=https://$APP.azurewebsites.net \
  --dart-define=IMAGE_PROXY_URL=https://$APP.azurewebsites.net
```

For campsite reservation fallback, point `RESERVATION_PROXY_URL` at the same
deployment:

```sh
flutter run \
  --dart-define=RESERVATION_PROXY_URL=https://$APP.azurewebsites.net
```

## Oracle Cloud

The campsite image endpoint also has a standalone Node build for an Oracle
Cloud VM or Container Instance. The NAVER credentials stay on the server.

```sh
npm ci
npm run build:oracle
PORT=8080 \
NAVER_API_HUB_CLIENT_ID=<your_client_id> \
NAVER_API_HUB_CLIENT_SECRET=<your_client_secret> \
npm run start:oracle
```

Or build and run the included container:

```sh
docker build -t campon-image-proxy .
docker run -d --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -e NAVER_API_HUB_CLIENT_ID=<your_client_id> \
  -e NAVER_API_HUB_CLIENT_SECRET=<your_client_secret> \
  campon-image-proxy
```

Expose it through the existing HTTPS reverse proxy, then build the app with:

```sh
flutter run --dart-define=IMAGE_PROXY_URL=https://<your-api-domain>
```

Health check: `GET /health`. Do not expose port 8080 directly to the internet;
terminate TLS and apply request rate limiting in the reverse proxy.

Before deployment, copy `.env.example` to `.env`, fill in the NAVER API HUB
credentials locally, and verify both search and image download:

```sh
npm run verify:naver -- "난지캠핑장" "서울"
```

The script prints only the response status, result count, image host, content
type, and byte size. It never prints the credentials.
