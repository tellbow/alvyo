// Command alvyo-cli reads Alvyo from the command line, with a personal
// access token (created under «Konto» on the website or in the app). It
// calls the API's MCP endpoint, so it answers as an AI assistant is
// answered; it can also be that endpoint for a local assistant (mcp).
//
//	alvyo-cli places <name>                          find places
//	alvyo-cli route plan <from> [<via>…] <to>        plan a route [--alpine] [--gpx]
//	alvyo-cli route <id>                             a route [--token t] [--gpx]
//	alvyo-cli routes                                 my routes and those shared with me
//	alvyo-cli journey <id>                           a journey with its stages [--token t]
//	alvyo-cli journeys                               my journeys and those shared with me
//	alvyo-cli reach <from>                           how far one gets in 2, 4, 8 h [--back] [--alpine]
//	alvyo-cli conditions <route id>                  weather, closures, protected areas [--date d]
//	alvyo-cli conditions <from> [<via>…] <to>        the same for a route planned from places
//	alvyo-cli discover --near <place>                public and official routes [--radius km]
//	                                                 [--official|--people] [--routes|--journeys]
//	                                                 [--sac-max n] [--min-hours h] [--max-hours h]
//	alvyo-cli mcp                                    serve the tools over stdio (Claude Desktop …)
//
// ALVYO_TOKEN holds the token; ALVYO_URL the server (default
// https://alvyo.tellbow.ch). --json prints the structured answer.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is set at build time: -ldflags "-X main.version=<tag>".
var version = "dev"

const usage = `Usage: alvyo-cli <command> [arguments] [--json]

  places <name>                     find places
  route plan <from> [<via>…] <to>   plan a route [--alpine] [--gpx]
  route <id>                        a route [--token t] [--gpx]
  routes                            my routes and those shared with me
  journey <id>                      a journey with its stages [--token t]
  journeys                          my journeys and those shared with me
  reach <from>                      how far one gets in 2, 4 and 8 h [--back] [--alpine]
  conditions <route id>             weather, closures, protected areas [--date YYYY-MM-DD]
  conditions <from> [<via>…] <to>   the same for a route planned from places
  discover --near <place>           public and official routes nearby [--radius km]
                                    [--official|--people] [--routes|--journeys]
                                    [--sac-max n] [--min-hours h] [--max-hours h]
  mcp                               serve the tools over stdio for a local AI assistant
  version                           this program's version

Places are names (Sargans, Chamanna Jenatsch) or "lat,lon".
ALVYO_TOKEN: a personal access token, from «Konto» on the website or in the app.
ALVYO_URL: the server, default https://alvyo.tellbow.ch.
`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	err := run(ctx, os.Args[1:], os.Stdout)
	stop()
	if err != nil {
		fmt.Fprintln(os.Stderr, "alvyo-cli:", err)
		if errors.Is(err, errUsage) {
			fmt.Fprint(os.Stderr, "\n"+usage)
			os.Exit(2)
		}
		os.Exit(1)
	}
}

var errUsage = errors.New("unknown command or arguments")

// flags without a value; all others take one.
var switches = map[string]bool{"json": true, "gpx": true, "alpine": true, "back": true,
	"official": true, "people": true, "routes": true, "journeys": true, "help": true}

// parse splits arguments into positional ones and flags, which may come
// anywhere: --gpx, --radius 5, --radius=5.
func parse(args []string) (pos []string, flags map[string]string, err error) {
	flags = map[string]string{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") || a == "-" {
			pos = append(pos, a)
			continue
		}
		name, value, hasValue := strings.Cut(strings.TrimLeft(a, "-"), "=")
		switch {
		case switches[name]:
			flags[name] = "true"
		case hasValue:
			flags[name] = value
		case i+1 < len(args):
			i++
			flags[name] = args[i]
		default:
			return nil, nil, fmt.Errorf("--%s needs a value", name)
		}
	}
	return pos, flags, nil
}

// call is one tool call: its name and arguments, and which structured
// field to print alone (the GPX) instead of the text.
type call struct {
	tool string
	args map[string]any
	only string
}

func run(ctx context.Context, args []string, out io.Writer) error {
	pos, flags, err := parse(args)
	if err != nil {
		return err
	}
	if len(pos) == 0 || flags["help"] != "" {
		_, err := fmt.Fprint(out, usage)
		return err
	}
	switch pos[0] {
	case "version":
		_, err := fmt.Fprintln(out, version)
		return err
	case "mcp":
		sess, err := connect(ctx)
		if err != nil {
			return err
		}
		defer func() { _ = sess.Close() }()
		return serveStdio(ctx, sess)
	}
	c, err := toolCall(pos, flags)
	if err != nil {
		return err
	}
	sess, err := connect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = sess.Close() }()
	res, err := sess.CallTool(ctx, &mcp.CallToolParams{Name: c.tool, Arguments: c.args})
	if err != nil {
		return err
	}
	return show(out, res, flags["json"] != "", c.only)
}

func toolCall(pos []string, flags map[string]string) (call, error) {
	profile := map[string]any{}
	if flags["alpine"] != "" {
		profile["profile"] = "alpine"
	}
	with := func(m map[string]any) map[string]any {
		for k, v := range profile {
			m[k] = v
		}
		return m
	}
	gpx := flags["gpx"] != ""
	only := ""
	if gpx {
		only = "gpx"
	}
	cmd, rest := pos[0], pos[1:]
	switch {
	case cmd == "places" && len(rest) > 0:
		return call{tool: "search_places", args: map[string]any{"query": strings.Join(rest, " ")}}, nil
	case cmd == "route" && len(rest) >= 3 && rest[0] == "plan":
		a := with(route(rest[1:]))
		a["gpx"] = gpx
		return call{tool: "plan_route", args: a, only: only}, nil
	case cmd == "route" && len(rest) == 1:
		return call{tool: "get_route", args: map[string]any{"id": rest[0], "token": flags["token"], "gpx": gpx}, only: only}, nil
	case cmd == "routes" && len(rest) == 0:
		return call{tool: "my_routes"}, nil
	case cmd == "journey" && len(rest) == 1:
		return call{tool: "get_journey", args: map[string]any{"id": rest[0], "token": flags["token"]}}, nil
	case cmd == "journeys" && len(rest) == 0:
		return call{tool: "my_journeys"}, nil
	case cmd == "reach" && len(rest) > 0:
		return call{tool: "reach", args: with(map[string]any{"from": strings.Join(rest, " "), "back": flags["back"] != ""})}, nil
	case cmd == "conditions" && len(rest) == 1:
		return call{tool: "route_conditions", args: map[string]any{"route_id": rest[0], "token": flags["token"], "date": flags["date"]}}, nil
	case cmd == "conditions" && len(rest) >= 2:
		a := with(route(rest))
		a["date"] = flags["date"]
		return call{tool: "route_conditions", args: a}, nil
	case cmd == "discover" && len(rest) == 0 && flags["near"] != "":
		a := map[string]any{"near": flags["near"]}
		for _, f := range []struct{ flag, arg string }{{"radius", "radius_km"}, {"sac-max", "sac_max"}, {"min-hours", "min_hours"}, {"max-hours", "max_hours"}} {
			if v := flags[f.flag]; v != "" {
				n, err := strconv.ParseFloat(v, 64)
				if err != nil {
					return call{}, fmt.Errorf("--%s is a number", f.flag)
				}
				a[f.arg] = n
			}
		}
		switch {
		case flags["official"] != "":
			a["official"] = "only"
		case flags["people"] != "":
			a["official"] = "none"
		}
		switch {
		case flags["routes"] != "":
			a["kind"] = "route"
		case flags["journeys"] != "":
			a["kind"] = "journey"
		}
		return call{tool: "discover", args: a}, nil
	}
	return call{}, errUsage
}

// route is from, via and to of places given in order.
func route(places []string) map[string]any {
	a := map[string]any{"from": places[0], "to": places[len(places)-1]}
	if len(places) > 2 {
		a["via"] = places[1 : len(places)-1]
	}
	return a
}

func show(out io.Writer, res *mcp.CallToolResult, asJSON bool, only string) error {
	var text strings.Builder
	for _, c := range res.Content {
		if t, ok := c.(*mcp.TextContent); ok {
			text.WriteString(t.Text)
		}
	}
	if res.IsError {
		return errors.New(strings.TrimSpace(text.String()))
	}
	switch {
	case only != "" && !asJSON:
		var fields map[string]any
		b, _ := json.Marshal(res.StructuredContent)
		_ = json.Unmarshal(b, &fields)
		s, _ := fields[only].(string)
		_, err := fmt.Fprint(out, s)
		return err
	case asJSON:
		b, err := json.MarshalIndent(res.StructuredContent, "", "  ")
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(out, string(b))
		return err
	}
	_, err := fmt.Fprint(out, text.String())
	return err
}

// tokenTransport sends the access token with every request.
type tokenTransport struct{ token string }

func (t tokenTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+t.token)
	r.Header.Set("User-Agent", "alvyo-cli/"+version)
	return http.DefaultTransport.RoundTrip(r)
}

func connect(ctx context.Context) (*mcp.ClientSession, error) {
	token := os.Getenv("ALVYO_TOKEN")
	if token == "" {
		return nil, errors.New("ALVYO_TOKEN is not set: create a personal access token under «Konto» on the website or in the app")
	}
	base := strings.TrimRight(os.Getenv("ALVYO_URL"), "/")
	if base == "" {
		base = "https://alvyo.tellbow.ch"
	}
	client := mcp.NewClient(&mcp.Implementation{Name: "alvyo-cli", Version: version}, nil)
	sess, err := client.Connect(ctx, &mcp.StreamableClientTransport{
		Endpoint:             base + "/api/v1/mcp",
		HTTPClient:           &http.Client{Transport: tokenTransport{token}, Timeout: 2 * time.Minute},
		DisableStandaloneSSE: true,
		MaxRetries:           -1,
	}, nil)
	if err != nil {
		return nil, fmt.Errorf("connecting to %s: %w", base, err)
	}
	return sess, nil
}

// serveStdio offers the server's tools on stdin and stdout, each call
// passed on: for assistants that start local programs, such as Claude
// Desktop.
func serveStdio(ctx context.Context, remote *mcp.ClientSession) error {
	init := remote.InitializeResult()
	server := mcp.NewServer(&mcp.Implementation{Name: "alvyo", Title: "Alvyo", Version: version},
		&mcp.ServerOptions{Instructions: init.Instructions})
	for tool, err := range remote.Tools(ctx, nil) {
		if err != nil {
			return err
		}
		server.AddTool(tool, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return remote.CallTool(ctx, &mcp.CallToolParams{Name: req.Params.Name, Arguments: req.Params.Arguments})
		})
	}
	return server.Run(ctx, &mcp.StdioTransport{})
}
