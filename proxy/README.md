# CampOn AI Proxy (Azure Functions)

Stateless proxy for the CampOn AI camping planner. It takes the app's request
(natural-language query + onboarding context + candidate campsites), fetches
camping weather from Open-Meteo, asks Google Gemini 2.0 Flash for a structured
plan, and returns it. When `GEMINI_API_KEY` is unset or the model fails, it
returns a deterministic fallback plan so the app never breaks.

It also serves the night preview: given the numbers the app already computed
(cloud, wind, night low, moon), Gemini writes a short first-person scene of that
night at that campsite. The same fallback rule applies — no key, no problem.

- Runtime: Azure Functions v4 (Node 20+), HTTP trigger, anonymous.
- Endpoints: `POST /api/plan`, `POST /api/preview`
- LLM: Google Gemini 2.0 Flash (free tier). Key in app setting `GEMINI_API_KEY`.
- Weather: Open-Meteo (free, keyless). `/api/preview` does not call it — the app
  sends its own numbers so the scene never contradicts the card the user saw.

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
  --settings GEMINI_API_KEY=<your_gemini_key>

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
