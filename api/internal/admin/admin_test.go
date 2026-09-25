package admin

import (
	"context"
	"errors"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestBan(t *testing.T) {
	ctx := context.Background()
	db := testdb.New(t)
	var uid string
	if err := db.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('b@example.ch', 'bad', 'Bad') RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ('\x01', $1, now() + interval '1 day')`, uid); err != nil {
		t.Fatal(err)
	}
	var rid string
	if err := db.QueryRow(ctx, `INSERT INTO routes (owner_id, title, visibility, anchors, legs, geom, distance_m, ascent_m, descent_m,
		duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
		VALUES ($1, 'Spam', 'public', '[]', '[]', ST_GeomFromText('LINESTRING Z (8 46 1, 8.1 46 1)', 4326), 0, 0, 0, 0, 0, 0, 0, 1, 1)
		RETURNING id`, uid).Scan(&rid); err != nil {
		t.Fatal(err)
	}

	if _, err := db.Exec(ctx, `INSERT INTO journeys (owner_id, title, visibility) VALUES ($1, 'Spam-Reise', 'public')`, uid); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO collections (owner_id, title, visibility) VALUES ($1, 'Spam-Liste', 'unlisted')`, uid); err != nil {
		t.Fatal(err)
	}

	if err := Ban(ctx, db, "bad"); err != nil {
		t.Fatal(err)
	}
	var sessions, shown int
	var visibility string
	var banned bool
	_ = db.QueryRow(ctx, `SELECT count(*) FROM sessions`).Scan(&sessions)
	_ = db.QueryRow(ctx, `SELECT visibility FROM routes WHERE id = $1`, rid).Scan(&visibility)
	_ = db.QueryRow(ctx, `SELECT banned_at IS NOT NULL FROM users WHERE id = $1`, uid).Scan(&banned)
	_ = db.QueryRow(ctx, `SELECT (SELECT count(*) FROM journeys WHERE visibility <> 'private')
		+ (SELECT count(*) FROM collections WHERE visibility <> 'private')`).Scan(&shown)
	if sessions != 0 || visibility != "private" || !banned || shown != 0 {
		t.Errorf("after ban: %d sessions, route %s, banned %v, %d journeys/collections still shared", sessions, visibility, banned, shown)
	}

	if err := Unban(ctx, db, "bad"); err != nil {
		t.Fatal(err)
	}
	if err := Ban(ctx, db, "nobody"); !errors.Is(err, ErrNotFound) {
		t.Errorf("ban unknown: %v", err)
	}
	if err := SetRole(ctx, db, "bad", "moderator"); err != nil {
		t.Errorf("set role: %v", err)
	}
	if err := SetRole(ctx, db, "bad", "emperor"); err == nil {
		t.Error("invalid role accepted")
	}
	if err := Unpublish(ctx, db, rid); err != nil {
		t.Errorf("unpublish: %v", err)
	}
}
