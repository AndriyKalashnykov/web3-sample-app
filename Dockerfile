# https://hub.docker.com/_/node/tags
FROM node:24.18.1-alpine@sha256:f70403e87646dc51b45295f4b8b70cdad0b63d2297c4c9899119b03f7af7a6b3
RUN apk --no-cache add git
RUN corepack enable pnpm

WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .

# Vite dev server reads PORT (vite.config.ts: `Number(process.env.PORT) || 8080`);
# single-source it through ARG → ENV → EXPOSE so the dev image stays tunable.
ARG APP_INTERNAL_PORT=8080
ENV PORT=${APP_INTERNAL_PORT}
EXPOSE ${APP_INTERNAL_PORT}

USER node
CMD ["pnpm", "run", "dev"]