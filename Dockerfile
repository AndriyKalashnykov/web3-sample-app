# https://hub.docker.com/_/node/tags
FROM node:24.14-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b
RUN apk --no-cache add git
RUN npm --global install pnpm

WORKDIR /app
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .
EXPOSE 8080
USER node
CMD ["pnpm", "run", "dev"]