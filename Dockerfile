# syntax=docker/dockerfile:1

# Use the official Node.js v22 base image
# We use the slim variant to keep the image size smaller while still having essential tools
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-slim AS base

# Configure pnpm installation directory and ensure it is on PATH
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install required system packages and pnpm, then clean up the apt cache for a smaller image
# ca-certificates: enables TLS/SSL for securely fetching dependencies and calling HTTPS services
# --no-install-recommends keeps the image minimal
RUN apt-get update -qq && apt-get install --no-install-recommends -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Pin pnpm version for reproducible builds
RUN npm install -g pnpm@10

# --- Build stage ---
# Install dependencies, build the project, and prepare production assets
FROM base AS build

# Create a new directory for our application code
# And set it as the working directory
WORKDIR /app

# Turn detector / HF assets use ~/.cache/huggingface (see @livekit/agents-plugin-livekit hf_utils).
# Build runs as root; default HOME=/root puts caches outside COPY /app, so models never ship in the image.
ENV HOME=/app
ENV XDG_CACHE_HOME=/app/.cache

# Copy workspace manifests so the initial `pnpm install` sees the full workspace graph
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/agent/package.json ./apps/agent/
COPY packages/internal/package.json ./packages/internal/

# Install dependencies using pnpm
# --frozen-lockfile ensures we use exact versions from pnpm-lock.yaml for reproducible builds
RUN pnpm install --frozen-lockfile

# Copy all remaining application files into the container
# This includes source code, configuration files, and dependency specifications
# (Excludes files specified in .dockerignore)
COPY . .

# Build the project
# Your package.json must contain a "build" script, such as `"build": "tsc"`
RUN pnpm build

# Pre-download any ML models or files the agent needs
# This ensures the container is ready to run immediately without downloading
# dependencies at runtime, which improves startup time and reliability
# Your package.json must contain a "download-files" script, such as `"download-files": "pnpm run build && node dist/agent.js download-files"`
RUN pnpm --filter agent download-files

# Do not run `pnpm prune --prod` here: at the workspace root it strips workspace packages'
# node_modules (e.g. apps/agent loses @livekit/agents-plugin-*), breaking `node dist/main.js`.

# --- Production stage ---
FROM base

# Create a non-privileged user that the app will run under
# See https://docs.docker.com/build/building/best-practices/#user
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/app" \
    --shell "/sbin/nologin" \
    --uid "${UID}" \
    appuser

WORKDIR /app

# Match runtime user home so Node resolves the same Hugging Face hub cache as during build.
ENV HOME=/app
ENV XDG_CACHE_HOME=/app/.cache

# Copy the built application with correct ownership in a single layer
# This avoids expensive recursive chown operations on node_modules
COPY --from=build --chown=appuser:appuser /app /app

USER appuser

# Set Node.js to production mode
ENV NODE_ENV=production

# Run the application (use `node` directly — `pnpm` needs a writable PNPM_HOME; /pnpm is root-owned)
# Matches apps/agent "start": node dist/main.js start
CMD [ "node", "apps/agent/dist/main.js", "start" ]