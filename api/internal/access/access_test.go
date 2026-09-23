package access

import "testing"

func TestRoleOf(t *testing.T) {
	const owner, other, token = "u-owner", "u-other", "tok"
	for _, tc := range []struct {
		name       string
		visibility string
		grant      Role
		user, tok  string
		want       Role
	}{
		{"owner of a private item", "private", None, owner, "", Owner},
		{"owner with a grant stays owner", "private", Viewer, owner, "", Owner},
		{"stranger, private", "private", None, other, "", None},
		{"anonymous, private", "private", None, "", "", None},
		{"token does not open private", "private", None, "", token, None},
		{"editor grant, private", "private", Editor, other, "", Editor},
		{"viewer grant, private", "private", Viewer, other, "", Viewer},
		{"public for anyone", "public", None, "", "", Viewer},
		{"editor grant on public", "public", Editor, other, "", Editor},
		{"unlisted without token", "unlisted", None, other, "", None},
		{"unlisted with token", "unlisted", None, "", token, Viewer},
		{"unlisted with wrong token", "unlisted", None, "", "nope", None},
		{"unlisted, grant without token", "unlisted", Editor, other, "", Editor},
	} {
		t.Run(tc.name, func(t *testing.T) {
			res := Resource{OwnerID: owner, Visibility: tc.visibility, ShareToken: token, Grant: tc.grant}
			if got := res.RoleOf(tc.user, tc.tok); got != tc.want {
				t.Errorf("got %s, want %s", got, tc.want)
			}
		})
	}
	if (Resource{Visibility: "unlisted"}).RoleOf("", "") != None {
		t.Error("an unlisted item without a token must not open with an empty token")
	}
}
