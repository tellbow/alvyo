GO_MODULES := swiss api
COMPOSE    := docker compose -f infra/compose.yaml

.PHONY: test test-go test-web lint lint-go lint-web check fmt build infra-up infra-down osm-fetch tlm-import places-import sqlc api-client

test: test-go test-web

test-go:
	go test ./swiss/... ./api/...

test-web:
	cd web && bun run test:unit --run --passWithNoTests

lint: lint-go lint-web

lint-go:
	@for m in $(GO_MODULES); do (cd $$m && golangci-lint run ./...) || exit 1; done

lint-web:
	cd web && bun run lint

check:
	cd web && bun run check

fmt:
	gofmt -w $(GO_MODULES)
	cd web && bun run format

# Load swissTLM3D hiking trails into the dev database (run `migrate` first).
tlm-import:
	$(COMPOSE) run --rm tlm-import

# Load stops, huts and accommodation (needs osm-fetch and migrate first).
places-import:
	$(COMPOSE) run --rm places-import

# Regenerate api/internal/dbq from api/queries/*.sql and the migrations.
sqlc:
	docker run --rm -v $(CURDIR)/api:/src -w /src sqlc/sqlc:1.31.1 generate

# Regenerate the web client types from the API's OpenAPI spec.
api-client:
	cd web && bun run gen:api

build:
	go build -o api/bin/odysgeh ./api/cmd/odysgeh
	cd web && bun run build

infra-up:
	$(COMPOSE) up -d

infra-down:
	$(COMPOSE) down

# Download + merge the OSM extracts (CH + LI) for GraphHopper. Delete
# infra/data/graph-cache afterwards to force a re-import.
osm-fetch:
	$(COMPOSE) run --rm osm-fetch
