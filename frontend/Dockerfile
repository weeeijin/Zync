# syntax=docker/dockerfile:1.7
# Targets:
#   dev   — Vite dev server with HMR (used by docker-compose.override.yml)
#   prod  — static build served by unprivileged nginx (default)

# ── Dependencies (cached layer) ─────────────────────────────────────────────
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# ── Development server ──────────────────────────────────────────────────────
FROM deps AS dev
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# ── Production build ────────────────────────────────────────────────────────
FROM deps AS build
# Empty = same origin (Caddy routes /api to the backend)
ARG VITE_API_BASE_URL=""
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
COPY . .
RUN npm run build

# ── Production runtime ──────────────────────────────────────────────────────
FROM nginxinc/nginx-unprivileged:1.27-alpine AS prod
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
# The base image already drops root; declare it explicitly so scanners and
# runtimes enforce it (uid 101 = nginx)
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
