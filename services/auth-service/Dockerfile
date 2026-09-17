# auth-service 通过 repo-root context 构建，以便取到 tsconfig.base.json。
# 保持与仓库一致的目录布局（/app/tsconfig.base.json + /app/services/auth-service/**），
# 使 tsconfig 的 `extends: ../../tsconfig.base.json` 正确解析。
FROM node:22-alpine AS builder
WORKDIR /app

# 仓库根基配置（auth-service tsconfig 继承它）
COPY tsconfig.base.json ./

# 在 /app/services/auth-service 下隔离构建（package.json 无 workspace:/file: 依赖）
WORKDIR /app/services/auth-service
COPY services/auth-service/package.json ./package.json
COPY services/auth-service/tsconfig.json ./tsconfig.json
RUN npm install
COPY services/auth-service/src ./src
RUN npx tsc

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app/services/auth-service/dist ./dist
COPY --from=builder /app/services/auth-service/node_modules ./node_modules
COPY --from=builder /app/services/auth-service/package.json ./
EXPOSE 8303
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8303/health || exit 1
CMD ["node", "dist/index.js"]
