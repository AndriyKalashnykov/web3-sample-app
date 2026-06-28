# https://hub.docker.com/_/node/tags
FROM node:24.18.0-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd
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