GO_MODULES := swiss api
COMPOSE    := docker compose -f infra/compose.yaml

.PHONY: test test-go test-web lint lint-go lint-web check fmt build infra-up infra-down osm-fetch tlm-import places-import alti-import wanderland-import weather-precip snow-cover sqlc api-client scorecard licenses

test: test-go test-web

test-go:
	go test ./swiss/... ./api/...

test-web:
	cd web && bun run test:unit --run --passWithNoTests

# The licenses of all Go, npm and Dart packages; fails on one not reviewed
# (after `bun install` in web and `flutter pub get` in app; docs/licensing.md).
licenses:
	python3 -I infra/ops/licenses.py

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

# The official routes of Wanderland Schweiz (run `migrate` first); the API
# makes them public routes and journeys of the account wanderland.
wanderland-import:
	$(COMPOSE) run --rm wanderland-import

# Rain pictures for the map (radar and forecast; run `migrate` first). The
# cluster runs it every 5 minutes.
weather-precip:
	$(COMPOSE) run --rm weather-precip

# swisstopo's height model (swissALTI3D, about 6 GB) as tiles into
# infra/data/alti, for ALVYO_SWISSALTI3D_DIR. All of Switzerland takes about
# 5 hours, later runs fetch only changed tiles; TILES="2600-1198 ..." for some.
alti-import:
	$(COMPOSE) run --rm alti-import $(TILES)

# Snow cover tiles for the map (Copernicus; run `migrate` first). The
# cluster looks for a new day every 6 hours.
snow-cover:
	$(COMPOSE) run --rm snow-cover

# Regenerate api/internal/dbq from api/queries/*.sql and the migrations.
sqlc:
	docker run --rm -v $(CURDIR)/api:/src -w /src sqlc/sqlc:1.31.1 generate

# Regenerate the web client types from the API's OpenAPI spec.
api-client:
	cd web && bun run gen:api

build:
	go build -o api/bin/alvyo ./api/cmd/alvyo
	cd web && bun run build

infra-up:
	$(COMPOSE) up -d

infra-down:
	$(COMPOSE) down

# Download + merge the OSM extracts (CH, LI, 15 km beyond) for GraphHopper. Delete
# infra/data/graph-cache afterwards to force a re-import.
osm-fetch:
	$(COMPOSE) run --rm osm-fetch

# OpenSSF Scorecard of the repository, as a checklist (with the GitHub CLI's
# login; a private repository cannot publish its score).
scorecard:
	GITHUB_AUTH_TOKEN=$$(gh auth token) go run github.com/ossf/scorecard/v5@v5.5.0 --repo=github.com/tellbow/alvyo --show-details
