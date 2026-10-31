package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"testing"

	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/photos/phototest"
)

// putAvatar uploads a profile picture and returns the new avatar id.
func (c *client) putAvatar(img []byte) (int, string) {
	c.t.Helper()
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	f, _ := w.CreateFormFile("file", "me.jpg")
	_, _ = f.Write(img)
	_ = w.Close()
	req, _ := http.NewRequest("PUT", c.base+"/api/v1/me/avatar", &b)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Origin", origin)
	resp, err := c.http.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(resp.Body)
	var me struct{ Avatar string }
	_ = json.Unmarshal(raw, &me)
	return resp.StatusCode, me.Avatar
}

func TestAvatars(t *testing.T) {
	var store *photos.Store
	s := newTestServerWith(t, func(d *Deps) {
		store = &photos.Store{DB: d.DB, Files: &photos.Files{Dir: t.TempDir()}}
		d.Photos = store
	})
	ctx := context.Background()
	anna, anon := s.client(t), s.client(t)
	s.signup(anna, "anna@example.ch", "anna")
	img := phototest.JPEG(800, 600, phototest.EXIF{})

	if code, _ := anon.putAvatar(img); code != http.StatusUnauthorized {
		t.Errorf("anonymous upload: %d", code)
	}
	if code, _ := anna.putAvatar([]byte("<svg/>")); code != http.StatusUnsupportedMediaType {
		t.Errorf("svg: %d", code)
	}
	code, first := anna.putAvatar(img)
	if code != http.StatusOK || first == "" {
		t.Fatalf("upload: %d %q", code, first)
	}
	// Anyone with the id gets the picture; the profile names it.
	if code, b := anon.do("GET", "/api/v1/avatars/"+first, nil); code != http.StatusOK || !bytes.HasPrefix(b, []byte{0xFF, 0xD8}) {
		t.Errorf("get: %d", code)
	}
	if _, b := anna.do("GET", "/api/v1/users/anna", nil); !bytes.Contains(b, []byte(`"avatar":"`+first+`"`)) {
		t.Errorf("profile: %s", b)
	}

	// Replacing it puts the old file in the trash, which the sweep removes.
	_, second := anna.putAvatar(img)
	if second == "" || second == first {
		t.Fatalf("second: %q", second)
	}
	if err := store.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if code, _ := anon.do("GET", "/api/v1/avatars/"+first, nil); code != http.StatusNotFound {
		t.Errorf("old picture after the sweep: %d", code)
	}

	// Removing it, and so with the account.
	if code, b := anna.do("DELETE", "/api/v1/me/avatar", nil); code != http.StatusOK || bytes.Contains(b, []byte(`"avatar"`)) {
		t.Errorf("delete: %d %s", code, b)
	}
	_ = store.Sweep(ctx)
	if code, _ := anon.do("GET", "/api/v1/avatars/"+second, nil); code != http.StatusNotFound {
		t.Errorf("removed picture: %d", code)
	}
	_, third := anna.putAvatar(img)
	if code, _ := anna.do("DELETE", "/api/v1/me", map[string]any{"password": "sehr-geheim-123"}); code != http.StatusNoContent {
		t.Fatalf("delete account: %d", code)
	}
	_ = store.Sweep(ctx)
	if code, _ := anon.do("GET", "/api/v1/avatars/"+third, nil); code != http.StatusNotFound {
		t.Errorf("picture of a deleted account: %d", code)
	}
}
