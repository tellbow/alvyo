// Package migrations embeds the SQL schema migrations (goose format).
package migrations

import "embed"

// FS holds the migration files.
//
//go:embed *.sql
var FS embed.FS
