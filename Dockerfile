# https://hub.docker.com/_/node/tags
FROM node:26.12.1-alpine@sha256:40cd011b55415bc894e45b02fdd5a5dfde056921b7d23a64c74f80497af48797
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

# Numeric form of the base image's `node` user (uid=1000 gid=1000) — hadolint
# DL3066: a name is only resolvable inside the image, a numeric id is not.
USER 1000:1000
CMD ["pnpm", "run", "dev"]