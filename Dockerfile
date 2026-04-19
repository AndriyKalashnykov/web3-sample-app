# https://hub.docker.com/_/node/tags
FROM node:24.15.0-alpine@sha256:8e2c930fda481a6ec141fe5a88e8c249c69f8102fe98af505f38c081649ea749
RUN apk --no-cache add git
RUN corepack enable pnpm

WORKDIR /app
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .
EXPOSE 8080
USER node
CMD ["pnpm", "run", "dev"]