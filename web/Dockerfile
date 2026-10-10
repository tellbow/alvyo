# The build output is plain JavaScript: build natively, run on any platform.
FROM --platform=$BUILDPLATFORM oven/bun:1.3-alpine AS build
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY . .
RUN bun run build \
 && rm -rf node_modules \
 && bun install --frozen-lockfile --production

# adapter-node bundles the devDependencies into build/; the dependencies
# (@opentelemetry/api, which SvelteKit imports itself) come as node_modules.
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=3000
COPY --from=build /app/build build
COPY --from=build /app/node_modules node_modules
COPY package.json ./
USER node
EXPOSE 3000
CMD ["node", "build"]
