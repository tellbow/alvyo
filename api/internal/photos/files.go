package photos

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/google/uuid"
)

// Sizes stored for every photo.
const (
	Large = "large"
	Thumb = "thumb"
)

// Files keeps photo files in a directory, spread over subdirectories by the
// first two characters of the id.
type Files struct {
	Dir string
}

func (f *Files) path(id uuid.UUID, size string) string {
	s := id.String()
	return filepath.Join(f.Dir, s[:2], s+"-"+size+".jpg")
}

// Write stores both sizes of a photo.
func (f *Files) Write(id uuid.UUID, p Processed) error {
	if err := os.MkdirAll(filepath.Dir(f.path(id, Large)), 0o750); err != nil {
		return err
	}
	for size, data := range map[string][]byte{Large: p.Large, Thumb: p.Thumb} {
		tmp := f.path(id, size) + ".tmp"
		if err := os.WriteFile(tmp, data, 0o640); err != nil {
			return err
		}
		if err := os.Rename(tmp, f.path(id, size)); err != nil {
			return err
		}
	}
	return nil
}

// Read returns one size of a photo.
func (f *Files) Read(id uuid.UUID, size string) ([]byte, error) {
	return os.ReadFile(f.path(id, size))
}

// Remove deletes all sizes of a photo; missing files are fine.
func (f *Files) Remove(id uuid.UUID) error {
	var errs []error
	for _, size := range []string{Large, Thumb} {
		if err := os.Remove(f.path(id, size)); err != nil && !errors.Is(err, fs.ErrNotExist) {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}
