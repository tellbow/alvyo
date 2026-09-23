# Build from the repository root: docker build -f api/Dockerfile .
# The build stage runs natively and cross-compiles for the target platform.
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build
WORKDIR /src
COPY go.work ./
COPY swiss/go.mod swiss/go.sum* swiss/
COPY api/go.mod api/go.sum api/
RUN cd api && go mod download
COPY swiss swiss
COPY api api
ARG VERSION=dev TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /odysgeh ./api/cmd/odysgeh
# Writable for the nonroot user; new Docker volumes mounted there take this owner.
RUN mkdir -p /out/cache /out/data/photos

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /odysgeh /odysgeh
COPY --from=build --chown=65532:65532 /out/ /
EXPOSE 8080
ENTRYPOINT ["/odysgeh"]
CMD ["serve"]
