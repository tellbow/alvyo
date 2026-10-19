package live

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"pgregory.net/rapid"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

// TestContactsModel runs random sequences of adding and deleting contacts,
// some at once, against a model: a map by address. Whatever the order, a
// hiker has at most MaxContacts and the store lists what the model holds.
func TestContactsModel(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	s := &Store{DB: pool}
	emails := []string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m"} // more than MaxContacts

	rapid.Check(t, func(t *rapid.T) {
		var owner uuid.UUID
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale)
			VALUES (gen_random_uuid() || '@example.ch', 'u' || substr(md5(random()::text), 1, 12), 'Anna', 'de') RETURNING id`).Scan(&owner); err != nil {
			t.Fatal(err)
		}
		model := map[string]Contact{} // by lower-case address
		email := rapid.Custom(func(t *rapid.T) string {
			e := rapid.SampledFrom(emails).Draw(t, "email") + "@example.ch"
			if rapid.Bool().Draw(t, "upper") {
				e = strings.ToUpper(e)
			}
			return e
		})
		name := rapid.StringMatching(`[A-Za-zäöü][a-zäöü ]{0,15}`)

		add := func(c Contact, err error, e string) {
			k := strings.ToLower(e)
			_, had := model[k]
			switch {
			case err == nil:
				if had || len(model) >= MaxContacts {
					t.Fatalf("added %s with %d contacts (had it: %v)", e, len(model), had)
				}
				model[k] = c
			case errors.Is(err, ErrDuplicate):
				if !had {
					t.Fatalf("%s refused as a duplicate", e)
				}
			case errors.Is(err, ErrTooMany): // also for an address it has, when full
				if len(model) < MaxContacts {
					t.Fatalf("%s refused with %d contacts", e, len(model))
				}
			default:
				t.Fatal(err)
			}
		}

		t.Repeat(map[string]func(*rapid.T){
			"add": func(t *rapid.T) {
				e := email.Draw(t, "email")
				c, err := s.AddContact(ctx, owner, name.Draw(t, "name"), e)
				add(c, err, e)
			},
			// Two phones adding at the same time: the limit holds anyway.
			"add at once": func(t *rapid.T) {
				es := rapid.SliceOfNDistinct(email, 2, 4, strings.ToLower).Draw(t, "emails")
				type result struct {
					c   Contact
					err error
				}
				res := make([]result, len(es))
				var wg sync.WaitGroup
				for i, e := range es {
					wg.Go(func() {
						res[i].c, res[i].err = s.AddContact(ctx, owner, "Gleichzeitig", e)
					})
				}
				wg.Wait()
				n := 0
				for i, r := range res {
					switch {
					case r.err == nil:
						n++
						model[strings.ToLower(es[i])] = r.c
					case errors.Is(r.err, ErrDuplicate), errors.Is(r.err, ErrTooMany):
					default:
						t.Fatal(r.err)
					}
				}
				if len(model) > MaxContacts {
					t.Fatalf("%d contacts after %d added at once", len(model), n)
				}
			},
			"delete": func(t *rapid.T) {
				if len(model) == 0 {
					t.Skip("none")
				}
				keys := make([]string, 0, len(model))
				for k := range model {
					keys = append(keys, k)
				}
				k := rapid.SampledFrom(keys).Draw(t, "contact")
				if err := s.DeleteContact(ctx, owner, uuid.MustParse(model[k].ID)); err != nil {
					t.Fatal(err)
				}
				delete(model, k)
			},
			"delete unknown": func(t *rapid.T) {
				if err := s.DeleteContact(ctx, owner, uuid.New()); !errors.Is(err, ErrNotFound) {
					t.Fatalf("unknown contact: %v", err)
				}
			},
			"": func(t *rapid.T) {
				got, err := s.Contacts(ctx, owner)
				if err != nil {
					t.Fatal(err)
				}
				if len(got) != len(model) {
					t.Fatalf("%d contacts, model %d", len(got), len(model))
				}
				for _, c := range got {
					if model[strings.ToLower(c.Email)] != c {
						t.Fatalf("%+v, model %+v", c, model[strings.ToLower(c.Email)])
					}
				}
			},
		})
	})
}

// TestAddContactAtOnce: phones adding the tenth contact at the same moment
// give ten contacts, not more.
func TestAddContactAtOnce(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	s := &Store{DB: pool}
	for round := range 20 {
		var owner uuid.UUID
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale)
			VALUES ($1, $2, 'Anna', 'de') RETURNING id`, fmt.Sprintf("anna%d@example.ch", round), fmt.Sprintf("anna%d", round)).Scan(&owner); err != nil {
			t.Fatal(err)
		}
		for i := range MaxContacts - 1 {
			if _, err := s.AddContact(ctx, owner, "X", fmt.Sprintf("x%d@example.ch", i)); err != nil {
				t.Fatal(err)
			}
		}
		start := make(chan struct{})
		var wg sync.WaitGroup
		for i := range 4 {
			wg.Go(func() {
				<-start
				_, _ = s.AddContact(ctx, owner, "Y", fmt.Sprintf("y%d@example.ch", i))
			})
		}
		close(start)
		wg.Wait()
		if got, _ := s.Contacts(ctx, owner); len(got) != MaxContacts {
			t.Fatalf("round %d: %d contacts", round, len(got))
		}
	}
}
