# ---- Stage 1: deps + build ----
# pnpm monorepo: a frozen-lockfile install requires every importer's package.json
# to be present, so we copy them all, then only the dashboard source for the build.
FROM node:22-alpine AS builder

# NEXT_PUBLIC_* 会在 `next build` 时内联进浏览器 bundle，
# 因此必须在构建期传入（用 ARG→ENV），运行时 environment 无效。
# 默认走宿主机映射端口（浏览器侧经 localhost:8310 访问 auth-service）。
ARG NEXT_PUBLIC_API_URL=http://localhost:8310/api/v1
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

WORKDIR /app

# corepack for pnpm 10 (matches repo packageManager)
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate

# Workspace root manifests
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json tsconfig.base.json ./

# package.json for every lockfile importer (keeps `--frozen-lockfile` consistent)
COPY apps/game-creator/package.json apps/game-creator/package.json
COPY apps/parent-dashboard/package.json apps/parent-dashboard/package.json
COPY services/auth-service/package.json services/auth-service/package.json
COPY services/content-filter-service/package.json services/content-filter-service/package.json
COPY services/content-service/package.json services/content-service/package.json
COPY services/dialogue-service/package.json services/dialogue-service/package.json
COPY services/quest-service/package.json services/quest-service/package.json
COPY services/reward-service/package.json services/reward-service/package.json
COPY services/spirit-coach-service/package.json services/spirit-coach-service/package.json
COPY tests/package.json tests/package.json

# Parent dashboard config files needed by the build
COPY apps/parent-dashboard/tsconfig.json apps/parent-dashboard/tsconfig.json
COPY apps/parent-dashboard/next.config.js apps/parent-dashboard/next.config.js
COPY apps/parent-dashboard/postcss.config.js apps/parent-dashboard/postcss.config.js
COPY apps/parent-dashboard/next-env.d.ts apps/parent-dashboard/next-env.d.ts

# Install all workspace dependencies (frozen lockfile to match repo)
RUN pnpm install --frozen-lockfile

# Copy the full dashboard source
COPY apps/parent-dashboard/ apps/parent-dashboard/

# Build the parent dashboard (Next.js standalone)
WORKDIR /app/apps/parent-dashboard
RUN pnpm build

# ---- Stage 2: runtime ----
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3333
ENV HOSTNAME=0.0.0.0

# Standalone output bundles server code + minimal node_modules (monorepo-rooted layout)
COPY --from=builder /app/apps/parent-dashboard/.next/standalone ./
COPY --from=builder /app/apps/parent-dashboard/.next/static ./apps/parent-dashboard/.next/static

EXPOSE 3333
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD wget -qO- http://127.0.0.1:3333/ || exit 1
CMD ["node", "apps/parent-dashboard/server.js"]
