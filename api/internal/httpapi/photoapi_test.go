package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/photos"
	"github.com/tellbow/odysgeh/api/internal/photos/phototest"
)

type photosResp struct {
	CanEdit bool `json:"can_edit"`
	Photos  []struct {
		ID       string    `json:"id"`
		Caption  string    `json:"caption"`
		Width    int       `json:"width"`
		Pin      []float64 `json:"pin"`
		Uploader string    `json:"uploader"`
		TakenAt  *string   `json:"taken_at"`
	} `json:"photos"`
}

// uploadPhoto posts an image with a caption.
func (c *client) uploadPhoto(path string, img []byte, caption string) (int, photosResp) {
	c.t.Helper()
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	_ = w.WriteField("caption", caption)
	f, _ := w.CreateFormFile("file", "photo.jpg")
	_, _ = f.Write(img)
	_ = w.Close()
	req, _ := http.NewRequest("POST", c.base+path, &b)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Origin", origin)
	resp, err := c.http.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(resp.Body)
	var out photosResp
	_ = json.Unmarshal(raw, &out)
	return resp.StatusCode, out
}

func (c *client) photos(path string) (int, photosResp) {
	c.t.Helper()
	code, raw := c.do("GET", path, nil)
	var out photosResp
	_ = json.Unmarshal(raw, &out)
	return code, out
}

func TestPhotos(t *testing.T) {
	dir := t.TempDir()
	s := newTestServerWith(t, func(d *Deps) {
		d.Photos = &photos.Store{DB: d.DB, Files: &photos.Files{Dir: dir}}
	})
	ctx := context.Background()
	signup := func(name string) *client {
		c := s.client(t)
		c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name))
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	owner, editor, viewer, mod, anon := signup("owner"), signup("edi"), signup("vie"), signup("mod"), s.client(t)
	if _, err := s.db.Exec(ctx, `UPDATE users SET role = 'moderator' WHERE username = 'mod'`); err != nil {
		t.Fatal(err)
	}

	// newRouteBody runs from (8.0, 46.5) to (8.004, 46.5).
	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "public"))
	var route savedRoute
	_ = json.Unmarshal(body, &route)
	r := "/api/v1/routes/" + route.ID
	owner.do("POST", r+"/grants", map[string]any{"username": "edi", "role": "editor"})
	owner.do("POST", r+"/grants", map[string]any{"username": "vie", "role": "viewer"})

	near := phototest.JPEG(800, 600, phototest.EXIF{Lon: 8.002, Lat: 46.5020, DateTime: "2026:07:04 10:00:00"}) // ~220 m off
	far := phototest.JPEG(800, 600, phototest.EXIF{Lon: 8.1, Lat: 46.5})                                        // ~7.6 km off
	var pngBuf bytes.Buffer
	_ = png.Encode(&pngBuf, image.NewRGBA(image.Rect(0, 0, 60, 40)))

	if code, _ := anon.uploadPhoto(r+"/photos", near, ""); code != http.StatusUnauthorized {
		t.Errorf("anonymous upload: %d", code)
	}
	if code, _ := viewer.uploadPhoto(r+"/photos", near, ""); code != http.StatusForbidden {
		t.Errorf("viewer upload: %d, want 403", code)
	}
	if code, _ := owner.uploadPhoto(r+"/photos", []byte("<svg/>"), ""); code != http.StatusUnsupportedMediaType {
		t.Errorf("svg upload: %d, want 415", code)
	}
	if code, _ := owner.uploadPhoto(r+"/photos", near, " Am Grat "); code != http.StatusOK {
		t.Fatalf("upload: %d", code)
	}
	owner.uploadPhoto(r+"/photos", far, "")
	code, ps := editor.uploadPhoto(r+"/photos", pngBuf.Bytes(), "Karte")
	if code != http.StatusOK || len(ps.Photos) != 3 || !ps.CanEdit {
		t.Fatalf("editor upload: %d %+v", code, ps)
	}
	p0, p1, p2 := ps.Photos[0], ps.Photos[1], ps.Photos[2]
	if p0.Caption != "Am Grat" || len(p0.Pin) != 2 || p0.TakenAt == nil || p0.Uploader != "owner" {
		t.Errorf("photo near the route: %+v", p0)
	}
	if p1.Pin != nil || p2.Pin != nil || p2.Uploader != "edi" || p2.Width != 60 {
		t.Errorf("far and png photos: %+v %+v", p1, p2)
	}

	// Anyone who may see the route sees the photos; the files have no EXIF.
	if code, ps := anon.photos(r + "/photos"); code != http.StatusOK || len(ps.Photos) != 3 || ps.CanEdit {
		t.Errorf("anonymous list: %d %+v", code, ps)
	}
	code, raw := anon.do("GET", "/api/v1/photos/"+p0.ID+"/thumb", nil)
	if code != http.StatusOK || !bytes.HasPrefix(raw, []byte{0xFF, 0xD8}) || bytes.Contains(raw, []byte("Exif")) {
		t.Errorf("thumb: %d, %d bytes", code, len(raw))
	}

	// Caption, pin and order.
	owner.do("PATCH", r+"/photos/"+p0.ID, map[string]any{"caption": "Gipfel", "unpin": true})
	if code, _ := viewer.do("PATCH", r+"/photos/"+p0.ID, map[string]any{"caption": "x"}); code != http.StatusForbidden {
		t.Errorf("viewer edits caption: %d", code)
	}
	_, raw = owner.do("PUT", r+"/photos/order", map[string]any{"ids": []string{p2.ID, p0.ID, p1.ID}})
	_ = json.Unmarshal(raw, &ps)
	if len(ps.Photos) != 3 || ps.Photos[0].ID != p2.ID || ps.Photos[1].Caption != "Gipfel" || ps.Photos[1].Pin != nil {
		t.Errorf("after edit and reorder: %s", raw)
	}
	if code, _ := owner.do("PUT", r+"/photos/order", map[string]any{"ids": []string{p2.ID}}); code != http.StatusUnprocessableEntity {
		t.Errorf("incomplete order: %d, want 422", code)
	}

	// Private routes keep their photos private; a reported photo stays
	// visible to moderators.
	viewer.do("POST", "/api/v1/reports", map[string]any{"kind": "photo", "id": p1.ID, "reason": "offensive"})
	owner.do("PATCH", r, map[string]any{"visibility": "private"}, "If-Match", `"1"`)
	if code, _ := anon.do("GET", "/api/v1/photos/"+p0.ID+"/large", nil); code != http.StatusNotFound {
		t.Errorf("photo of a private route: %d, want 404", code)
	}
	if code, _ := mod.do("GET", "/api/v1/photos/"+p1.ID+"/large", nil); code != http.StatusOK {
		t.Errorf("moderator views a reported photo: %d", code)
	}
	if code, _ := mod.do("GET", "/api/v1/photos/"+p0.ID+"/large", nil); code != http.StatusNotFound {
		t.Errorf("moderator views an unreported private photo: %d, want 404", code)
	}

	// Deleting a photo removes its files at once; deleting the route removes
	// the rest with the next sweep.
	owner.do("DELETE", r+"/photos/"+p0.ID, nil)
	store := &photos.Store{DB: s.db, Files: &photos.Files{Dir: dir}}
	if _, err := store.Files.Read(uuidOf(t, p0.ID), photos.Large); err == nil {
		t.Error("deleted photo still on disk")
	}
	if code, _ := owner.do("DELETE", r, nil); code != http.StatusNoContent {
		t.Fatalf("delete route: %d", code)
	}
	if err := store.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{p1.ID, p2.ID} {
		if _, err := store.Files.Read(uuidOf(t, id), photos.Thumb); err == nil {
			t.Errorf("photo %s of the deleted route still on disk", id)
		}
	}
	var trash int
	_ = s.db.QueryRow(ctx, `SELECT count(*) FROM photo_trash`).Scan(&trash)
	if trash != 0 {
		t.Errorf("%d photos left in the trash", trash)
	}
}

func uuidOf(t *testing.T, s string) uuid.UUID {
	t.Helper()
	id, err := uuid.Parse(s)
	if err != nil {
		t.Fatal(err)
	}
	return id
}
