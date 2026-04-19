#!/usr/bin/env sh
#
# Substitute runtime env vars into the bundled SPA JS, then start nginx.
# Vite bakes literal `$VITE_*` placeholders into the bundle (per Dockerfile.prod
# build args); envsubst replaces them at startup with the values from the env
# (typically supplied by the k8s ConfigMap).

set -eu

cp /usr/share/nginx/html/assets/*.js /tmp
EXISTING_VARS=$(printenv | awk -F= '{print "$"$1}' | paste -sd,)
export EXISTING_VARS

for file in /tmp/*.js; do
  envsubst "${EXISTING_VARS}" < "${file}" > "/usr/share/nginx/html/assets/$(basename "${file}")"
done

exec nginx -g 'daemon off;'