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
	// A profile picture has only this one size.
	AvatarSize = "avatar"
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

// WriteAvatar stores a profile picture made by Avatar.
func (f *Files) WriteAvatar(id uuid.UUID, jpg []byte) error {
	p := f.path(id, AvatarSize)
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	if err := os.WriteFile(p+".tmp", jpg, 0o640); err != nil {
		return err
	}
	return os.Rename(p+".tmp", p)
}

// Read returns one size of a photo.
func (f *Files) Read(id uuid.UUID, size string) ([]byte, error) {
	return os.ReadFile(f.path(id, size))
}

// Remove deletes all sizes of a photo or a profile picture; missing files are fine.
func (f *Files) Remove(id uuid.UUID) error {
	var errs []error
	for _, size := range []string{Large, Thumb, AvatarSize} {
		if err := os.Remove(f.path(id, size)); err != nil && !errors.Is(err, fs.ErrNotExist) {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}
