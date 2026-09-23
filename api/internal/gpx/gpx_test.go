package gpx

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestWriteValidatesAgainstSchema(t *testing.T) {
	var buf bytes.Buffer
	err := Write(&buf, Track{
		Name:        "Gaflei – Sargans <Etappe 1>",
		Description: "Via Alpina & more",
		Author:      "anna",
		Link:        "https://odysgeh.example/routes/1",
		Points:      [][3]float64{{9.5428, 47.1447, 1483.2}, {9.5, 47.1, 900}, {9.4456, 47.0449, 482.1}},
		Time:        time.Date(2026, 9, 22, 10, 0, 0, 0, time.UTC),
	})
	if err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	for _, want := range []string{`<trkpt lat="47.1447" lon="9.5428">`, "<ele>1483.2</ele>", "&lt;Etappe 1&gt;", "OpenStreetMap contributors"} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in\n%s", want, out)
		}
	}

	xmllint, err := exec.LookPath("xmllint")
	if err != nil {
		t.Skip("xmllint not installed")
	}
	file := filepath.Join(t.TempDir(), "route.gpx")
	if err := os.WriteFile(file, buf.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	if msg, err := exec.Command(xmllint, "--noout", "--schema", "testdata/gpx.xsd", file).CombinedOutput(); err != nil {
		t.Errorf("schema validation failed: %v\n%s", err, msg)
	}
}

func TestFilename(t *testing.T) {
	cases := map[string]string{
		"Bachalpsee Runde":         "bachalpsee-runde.gpx",
		"Grüsch → Schiers, Tag 2!": "gruesch-schiers-tag-2.gpx",
		"   ":                      "route.gpx",
	}
	for in, want := range cases {
		if got := Filename(in); got != want {
			t.Errorf("Filename(%q) = %q, want %q", in, got, want)
		}
	}
}
