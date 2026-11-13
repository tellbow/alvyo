# The build output is plain JavaScript: build natively, run on any platform.
FROM --platform=$BUILDPLATFORM oven/bun:1.4-alpine@sha256:4cf82f5686b196504fe119db3fcd9185b191f82ece82c40680e597228ec6070a AS build
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
