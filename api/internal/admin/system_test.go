package admin

import (
	"os"
	"path/filepath"
	"testing"
)

// A volume's lost+found is not the API's to read: skipped, not an error.
func TestNewestFileSkipsUnreadableDirs(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "tile.tif"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	locked := filepath.Join(dir, "lost+found")
	if err := os.Mkdir(locked, 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o700) })
	at, n, err := newestFile(dir)
	if err != nil || n != 1 || at.IsZero() {
		t.Errorf("newestFile: %v, %d files, %v", err, n, at)
	}
	if _, _, err := newestFile(filepath.Join(dir, "missing")); err == nil {
		t.Error("a missing directory is an error")
	}
}
