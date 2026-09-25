// Package mailer sends transactional e-mail (verification, password reset).
package mailer

import (
	"context"
	"fmt"
	"sync"
	"time"

	gomail "github.com/wneessen/go-mail"
)

// Message is a plain-text e-mail.
type Message struct {
	To      string
	Subject string
	Text    string
}

// Sender delivers messages.
type Sender interface {
	Send(ctx context.Context, m Message) error
}

// SMTPConfig configures the SMTP sender.
type SMTPConfig struct {
	Host     string
	Port     int
	Username string // empty: no authentication
	Password string
	TLS      string // "none", "starttls" or "tls"
	From     string // e.g. "Alvyo <noreply@alvyo.ch>"
}

// SMTP sends mail through an SMTP server.
type SMTP struct {
	client *gomail.Client
	from   string
}

// NewSMTP returns an SMTP sender. It does not connect until the first Send.
func NewSMTP(c SMTPConfig) (*SMTP, error) {
	opts := []gomail.Option{gomail.WithPort(c.Port), gomail.WithTimeout(15 * time.Second)}
	switch c.TLS {
	case "none", "":
		opts = append(opts, gomail.WithTLSPolicy(gomail.NoTLS))
	case "starttls":
		opts = append(opts, gomail.WithTLSPolicy(gomail.TLSMandatory))
	case "tls":
		opts = append(opts, gomail.WithSSL())
	default:
		return nil, fmt.Errorf("mail: unknown TLS mode %q", c.TLS)
	}
	if c.Username != "" {
		opts = append(opts, gomail.WithSMTPAuth(gomail.SMTPAuthPlain),
			gomail.WithUsername(c.Username), gomail.WithPassword(c.Password))
	}
	client, err := gomail.NewClient(c.Host, opts...)
	if err != nil {
		return nil, fmt.Errorf("mail: %w", err)
	}
	return &SMTP{client: client, from: c.From}, nil
}

// Send implements Sender.
func (s *SMTP) Send(ctx context.Context, m Message) error {
	msg := gomail.NewMsg()
	if err := msg.From(s.from); err != nil {
		return fmt.Errorf("mail: from: %w", err)
	}
	if err := msg.To(m.To); err != nil {
		return fmt.Errorf("mail: to: %w", err)
	}
	msg.Subject(m.Subject)
	msg.SetBodyString(gomail.TypeTextPlain, m.Text)
	if err := s.client.DialAndSendWithContext(ctx, msg); err != nil {
		return fmt.Errorf("mail: %w", err)
	}
	return nil
}

// Recorder is a Sender that keeps messages in memory, for tests.
type Recorder struct {
	mu   sync.Mutex
	sent []Message
}

// Send implements Sender.
func (r *Recorder) Send(_ context.Context, m Message) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sent = append(r.sent, m)
	return nil
}

// Sent returns a copy of all recorded messages.
func (r *Recorder) Sent() []Message {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]Message(nil), r.sent...)
}
