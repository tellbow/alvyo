// Package access decides who may see and change a route or journey.
//
// The owner owns it; a grant gives its role (viewer or editor); anyone may
// view public items and unlisted ones with their share token. Everyone else
// gets "not found", so private items are not revealed as existing.
package access

import "crypto/subtle"

// Role is what a caller may do, in increasing order.
type Role int

// Roles, each including the ones before.
const (
	None   Role = iota
	Viewer      // see, download
	Editor      // also change the content (stages, routes, notes …)
	Owner       // also visibility, share link, invitations, delete
)

func (r Role) String() string {
	switch r {
	case Viewer:
		return "viewer"
	case Editor:
		return "editor"
	case Owner:
		return "owner"
	}
	return ""
}

// ParseGrant reads a grant role as stored ("viewer", "editor").
func ParseGrant(s string) Role {
	switch s {
	case "viewer":
		return Viewer
	case "editor":
		return Editor
	}
	return None
}

// Resource is what decides access to one item.
type Resource struct {
	OwnerID    string
	Visibility string // private, unlisted, public
	ShareToken string
	Grant      Role // the caller's best grant; None without
}

// RoleOf returns the role of the caller (userID "" when anonymous) who
// presented token ("" without).
func (res Resource) RoleOf(userID, token string) Role {
	if userID != "" && userID == res.OwnerID {
		return Owner
	}
	role := res.Grant
	if role < Viewer && visible(res.Visibility, res.ShareToken, token) {
		role = Viewer
	}
	return role
}

func visible(visibility, shareToken, token string) bool {
	switch visibility {
	case "public":
		return true
	case "unlisted":
		return token != "" && shareToken != "" && subtle.ConstantTimeCompare([]byte(token), []byte(shareToken)) == 1
	}
	return false
}
