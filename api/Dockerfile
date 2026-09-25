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
# nodynamic: HEIC photos are decoded by the embedded WebAssembly decoder,
# never a system libheif.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -tags nodynamic -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /alvyo ./api/cmd/alvyo
# Writable for the nonroot user; new Docker volumes mounted there take this owner.
RUN mkdir -p /out/cache /out/data/photos

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /alvyo /alvyo
COPY --from=build --chown=65532:65532 /out/ /
EXPOSE 8080
ENTRYPOINT ["/alvyo"]
CMD ["serve"]
