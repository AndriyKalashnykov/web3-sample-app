# https://hub.docker.com/_/node/tags
FROM node:24.14-alpine
RUN apk --no-cache add git
RUN npm --global install pnpm

WORKDIR /app
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .
EXPOSE 8080
CMD ["pnpm", "run", "dev"]