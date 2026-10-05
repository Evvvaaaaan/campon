FROM node:22-alpine AS build

WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY api ./api
RUN npm run build:oracle

FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
COPY --from=build /app/dist/server.js ./server.js
USER node
EXPOSE 8080
CMD ["node", "server.js"]
