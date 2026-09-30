FROM node:22-alpine AS node-builder

WORKDIR /backend

COPY package.json tsconfig.json ./
RUN npm install

COPY src ./src
COPY tests ./tests
RUN npm run type-check && npm run build && node tests/rating_model_smoke.js

FROM heroiclabs/nakama:3.41.0

COPY --from=node-builder /backend/build/index.js /nakama/data/modules/build/index.js
COPY local.yml /nakama/data/local.yml
