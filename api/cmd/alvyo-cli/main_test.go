package main

import (
	"errors"
	"reflect"
	"testing"
)

func TestToolCall(t *testing.T) {
	for _, c := range []struct {
		args []string
		want call
	}{
		{[]string{"route", "plan", "Sargans", "Weisstannen", "--gpx"},
			call{tool: "plan_route", args: map[string]any{"from": "Sargans", "to": "Weisstannen", "gpx": true}, only: "gpx"}},
		{[]string{"route", "plan", "--alpine", "Sargans", "Vättis", "Weisstannen"},
			call{tool: "plan_route", args: map[string]any{"from": "Sargans", "via": []string{"Vättis"}, "to": "Weisstannen", "profile": "alpine", "gpx": false}}},
		{[]string{"discover", "--near", "Thun", "--official", "--radius=5"},
			call{tool: "discover", args: map[string]any{"near": "Thun", "official": "only", "radius_km": 5.0}}},
		{[]string{"places", "Piz", "Palü"}, call{tool: "search_places", args: map[string]any{"query": "Piz Palü"}}},
		{[]string{"routes", "--json"}, call{tool: "my_routes"}},
		{[]string{"conditions", "Sargans", "Weisstannen", "--date", "2026-10-12"},
			call{tool: "route_conditions", args: map[string]any{"from": "Sargans", "to": "Weisstannen", "date": "2026-10-12"}}},
	} {
		pos, flags, err := parse(c.args)
		if err != nil {
			t.Fatal(err)
		}
		got, err := toolCall(pos, flags)
		if err != nil || !reflect.DeepEqual(got, c.want) {
			t.Errorf("%v: %+v %v, want %+v", c.args, got, err, c.want)
		}
	}
	for _, args := range [][]string{{"route", "plan", "Sargans"}, {"discover"}, {"routes", "mine"}, {"hike"}} {
		pos, flags, _ := parse(args)
		if _, err := toolCall(pos, flags); !errors.Is(err, errUsage) {
			t.Errorf("%v: %v", args, err)
		}
	}
	if _, _, err := parse([]string{"discover", "--near"}); err == nil {
		t.Error("--near without a value")
	}
}
