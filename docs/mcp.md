# AI assistants and the command line

Alvyo can be read by AI assistants through MCP (Model Context Protocol) and
from the command line with `alvyo-cli`. Both use a personal access token
and only read: they plan, search and look, but never save or change
anything (requirement 71 in [plan.md](plan.md)).

## A token

On the website under «Konto» → «Zugriffstoken für KI-Assistenten und
Skripte», or in the app under «Profil» → «Konto» → «Zugriffstoken»: give it
a name (what it is for) and create it. The token (`alvyo_pat_…`) is shown
only then; copy it. The list shows when each was last used; «Widerrufen»
ends one at once. A password reset removes all of them.

A token reads everything the account may see, its e-mail address
included. Give it only to programs you trust, one token per program, so
that one can be revoked alone.

## Claude Code

```sh
claude mcp add --transport http alvyo https://alvyo.tellbow.ch/api/v1/mcp \
  --header "Authorization: Bearer alvyo_pat_…"
```

The website shows this line with the new token filled in. `claude mcp
list` should then list `alvyo` as connected; ask for instance «Plane eine
Wanderung von Sargans nach Weisstannen und sag mir, wie das Wetter wird».

## Claude Desktop and other local assistants

Claude Desktop starts local programs as MCP servers; `alvyo-cli mcp` is one
that passes every call on to Alvyo. Put `alvyo-cli` somewhere (the
binaries come with each [release](https://github.com/tellbow/alvyo/releases),
or `go build ./api/cmd/alvyo-cli`) and add to
`claude_desktop_config.json` (Settings → Developer → Edit Config):

```json
{
  "mcpServers": {
    "alvyo": {
      "command": "/usr/local/bin/alvyo-cli",
      "args": ["mcp"],
      "env": { "ALVYO_TOKEN": "alvyo_pat_…" }
    }
  }
}
```

Restart Claude Desktop; the tools appear under «alvyo». Other assistants
that speak streamable HTTP can use the address
`https://alvyo.tellbow.ch/api/v1/mcp` with the header `Authorization:
Bearer alvyo_pat_…` directly. Connectors that require OAuth (claude.ai,
ChatGPT) are not supported.

## The tools

| Tool | What |
|---|---|
| `search_places` | Places by name: villages, stops, huts, summits, passes, addresses |
| `plan_route` | From, via and to (names or `lat,lon`), hike or alpine: distance, ascent, Swiss hiking time (also at one's pace), SAC grade; GPX on request. Places more than 40 km apart are refused |
| `reach` | How far one gets from a place in 2, 4 and 8 hours, or there and back |
| `route_conditions` | Weather, closed trails, shooting, protected areas and snow (with the steep part) along a saved route or one planned from places |
| `discover` | Public routes and the official routes of Wanderland Schweiz around a place, with filters |
| `my_routes`, `my_journeys` | One's own and those shared with one |
| `get_route`, `get_journey` | One route (GPX on request) or journey with its stages |

Each answers with a short text and the same as structured JSON. Hiking
times «at your pace» use the pace set in the account. Limits: 60 requests
at once per token and then one a second; planning, reach and place
searches count against the account's limits as on the website.

## alvyo-cli

```sh
export ALVYO_TOKEN=alvyo_pat_…
alvyo-cli places Weisstannen
alvyo-cli route plan Sargans Weisstannen            # text
alvyo-cli route plan Sargans Weisstannen --gpx > sargans-weisstannen.gpx
alvyo-cli route plan --alpine Pontresina "Chamanna Boval" Morteratsch
alvyo-cli reach Kandersteg --back
alvyo-cli conditions Sargans Weisstannen --date 2026-10-12
alvyo-cli discover --near Thun --official --radius 15
alvyo-cli routes --json
alvyo-cli route <id> --gpx
alvyo-cli journeys
alvyo-cli journey <id>
```

`ALVYO_URL` points it at another server (default
`https://alvyo.tellbow.ch`; locally `http://localhost:8080`). It calls the
same MCP tools, so the CLI and an assistant get the same answers; `--json`
prints the structured one.
