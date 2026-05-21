FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
RUN npx tsc

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
EXPOSE 8302
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8302/health || exit 1
CMD ["node", "dist/index.js"]
