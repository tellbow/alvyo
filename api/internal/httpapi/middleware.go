package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/klauspost/compress/gzhttp"

	"github.com/tellbow/alvyo/api/internal/auth"
)

const sessionCookie = "alvyo_session"

type ctxKey int

const (
	ipKey ctxKey = iota
	tokenKey
)

// clientIP returns the caller's IP as determined by withClientIP.
func clientIP(ctx context.Context) string {
	ip, _ := ctx.Value(ipKey).(string)
	return ip
}

// limitKey is the caller's address for per-address limits: an IPv6
// address by its /64, which one connection usually has all of.
func limitKey(ctx context.Context) string {
	ip := clientIP(ctx)
	if a, err := netip.ParseAddr(ip); err == nil && a.Is6() && !a.Is4In6() {
		p, _ := a.Prefix(64)
		return p.String()
	}
	return ip
}

// sessionToken returns the session token of the request, if any.
func sessionToken(ctx context.Context) string {
	t, _ := ctx.Value(tokenKey).(string)
	return t
}

// withClientIP records the client IP. Behind our own reverse proxy (Caddy)
// the last X-Forwarded-For entry is the one the proxy appended.
func withClientIP(next http.Handler, trustProxy bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			ip = r.RemoteAddr
		}
		// Several header lines are one list; the client may send the first.
		if xff := r.Header.Values("X-Forwarded-For"); trustProxy && len(xff) > 0 {
			parts := strings.Split(xff[len(xff)-1], ",")
			ip = strings.TrimSpace(parts[len(parts)-1])
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ipKey, ip)))
	})
}

// withSession resolves the session cookie or bearer token to a user.
// Sessions slide: when the service extends one, the cookie is renewed too.
func withSession(next http.Handler, svc *auth.Service, secure bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, fromCookie := "", false
		if c, err := r.Cookie(sessionCookie); err == nil && c.Value != "" {
			token, fromCookie = c.Value, true
		} else if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
		if token == "" {
			next.ServeHTTP(w, r)
			return
		}

		ctx := r.Context()
		u, extended, err := svc.SessionUser(ctx, token)
		switch {
		case err == nil:
			ctx = auth.WithUser(ctx, u)
			ctx = context.WithValue(ctx, tokenKey, token)
			if extended != nil && fromCookie {
				c := newSessionCookie(token, *extended, secure)
				http.SetCookie(w, &c)
			}
		case errors.Is(err, auth.ErrNoSession), errors.Is(err, auth.ErrBanned):
			if fromCookie {
				c := clearSessionCookie(secure)
				http.SetCookie(w, &c)
			}
		default:
			slog.ErrorContext(ctx, "session lookup", "err", err)
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// withOriginCheck rejects cross-site state-changing requests (CSRF). Browsers
// send Origin and Sec-Fetch-Site on such requests; non-browser clients (the
// app, curl) send neither and authenticate with a bearer token.
func withOriginCheck(next http.Handler, allowedOrigin string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet, http.MethodHead, http.MethodOptions:
		default:
			if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
				http.Error(w, "cross-site request rejected", http.StatusForbidden)
				return
			}
			if o := r.Header.Get("Origin"); o != "" && o != allowedOrigin {
				http.Error(w, "origin not allowed", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// Unwrap lets http.ResponseController reach the connection, e.g. to extend
// the write deadline of a long download.
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// withAccessLog logs every request at debug level and server errors at error.
// withSecurityHeaders sets headers every response needs, independent of the
// reverse proxy in front.
func withSecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		next.ServeHTTP(w, r)
	})
}

func withAccessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		level := slog.LevelDebug
		if rec.status >= 500 {
			level = slog.LevelError
		}
		slog.Log(r.Context(), level, "request", "method", r.Method, "path", r.URL.Path,
			"status", rec.status, "duration", time.Since(start), "ip", clientIP(r.Context()))
	})
}

func newSessionCookie(token string, expires time.Time, secure bool) http.Cookie {
	return http.Cookie{
		Name:     sessionCookie,
		Value:    token,
		Path:     "/",
		Expires:  expires,
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteLaxMode,
	}
}

func clearSessionCookie(secure bool) http.Cookie {
	return http.Cookie{
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteLaxMode,
	}
}

// compressible are the answers worth compressing: JSON, GPX and text.
// Photos, offline map packs and zips are compressed already, and a pack
// download must keep its byte ranges for resuming.
var compressible = []string{
	"application/json", "application/problem+json", "application/gpx+xml",
	"application/xml", "image/svg+xml", "text/plain", "text/html", "text/csv",
}

// withCompression gzips (or zstd-compresses) text answers of 1 KB or more.
func withCompression(next http.Handler) http.Handler {
	wrap, err := gzhttp.NewWrapper(gzhttp.ContentTypes(compressible), gzhttp.MinSize(1024))
	if err != nil {
		panic(err) // fixed options
	}
	return wrap(next)
}
