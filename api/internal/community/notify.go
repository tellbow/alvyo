package community

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

// mailInterval is the least time between two notification e-mails on the
// same topic to the same person.
const mailInterval = 15 * time.Minute

// recipient is who a notification goes to, if they want it.
type recipient struct {
	email, locale string
}

// wants returns the recipient if they have a verified address, are not
// banned and want notifications of the kind (the users column).
func (s *Store) wants(ctx context.Context, user uuid.UUID, column string) (recipient, bool) {
	var r recipient
	var on bool
	err := s.DB.QueryRow(ctx, `SELECT email, locale, `+column+` FROM users
		WHERE id = $1 AND email_verified_at IS NOT NULL AND banned_at IS NULL`, user).Scan(&r.email, &r.locale, &on)
	return r, err == nil && on
}

// due reports whether a mail on topic may go to user now, and if so records
// it as sent.
func (s *Store) due(ctx context.Context, user uuid.UUID, topic string) bool {
	var ok bool
	err := s.DB.QueryRow(ctx, `INSERT INTO mail_throttle (user_id, topic, sent_at) VALUES ($1, $2, now())
		ON CONFLICT (user_id, topic) DO UPDATE SET sent_at = now()
			WHERE mail_throttle.sent_at < now() - make_interval(secs => $3)
		RETURNING true`, user, topic, mailInterval.Seconds()).Scan(&ok)
	return err == nil && ok
}

func (s *Store) send(ctx context.Context, m mailer.Message) {
	if err := s.Mail.Send(ctx, m); err != nil {
		slog.ErrorContext(ctx, "notification e-mail", "err", err)
	}
}

func (s *Store) notifyComment(ctx context.Context, t Target, author dbq.User, body string) {
	r, ok := s.wants(ctx, t.OwnerID, "notify_comments")
	if !ok || !s.due(ctx, t.OwnerID, "comments:"+t.ID.String()) {
		return
	}
	link := s.PublicURL + "/" + t.Kind.table() + "/" + t.ID.String()
	if runes := []rune(body); len(runes) > 300 {
		body = string(runes[:300]) + " …"
	}
	switch r.locale {
	case "fr":
		what := map[Kind]string{Route: "ton itinéraire", Journey: "ta randonnée par étapes"}[t.Kind]
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s a commenté « %s »", author.DisplayName, t.Title),
			Text: fmt.Sprintf("Bonjour\n\n%s (@%s) a commenté %s « %s » :\n\n%s\n\n%s\n\n"+
				"Les autres commentaires des 15 prochaines minutes s'y trouvent aussi, sans e-mail supplémentaire.\n"+
				"Régler les notifications : %s/account\n", author.DisplayName, author.Username, what, t.Title, body, link, s.PublicURL),
		})
		return
	case "it":
		what := map[Kind]string{Route: "il tuo percorso", Journey: "il tuo trekking a tappe"}[t.Kind]
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s ha commentato «%s»", author.DisplayName, t.Title),
			Text: fmt.Sprintf("Ciao\n\n%s (@%s) ha commentato %s «%s»:\n\n%s\n\n%s\n\n"+
				"Gli altri commenti dei prossimi 15 minuti li trovi lì, senza un'altra e-mail.\n"+
				"Impostazioni delle notifiche: %s/account\n", author.DisplayName, author.Username, what, t.Title, body, link, s.PublicURL),
		})
		return
	case "de":
		what := map[Kind]string{Route: "deine Route", Journey: "deine Etappentour"}[t.Kind]
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s hat «%s» kommentiert", author.DisplayName, t.Title),
			Text: fmt.Sprintf("Hallo\n\n%s (@%s) hat %s «%s» kommentiert:\n\n%s\n\n%s\n\n"+
				"Weitere Kommentare der nächsten 15 Minuten siehst du dort, ohne eigene E-Mail.\n"+
				"Benachrichtigungen einstellen: %s/account\n", author.DisplayName, author.Username, what, t.Title, body, link, s.PublicURL),
		})
		return
	}
	what := map[Kind]string{Route: "your route", Journey: "your journey"}[t.Kind]
	s.send(ctx, mailer.Message{
		To:      r.email,
		Subject: fmt.Sprintf("%s commented on “%s”", author.DisplayName, t.Title),
		Text: fmt.Sprintf("Hi\n\n%s (@%s) commented on %s “%s”:\n\n%s\n\n%s\n\n"+
			"Further comments in the next 15 minutes are there too, without another e-mail.\n"+
			"Notification settings: %s/account\n", author.DisplayName, author.Username, what, t.Title, body, link, s.PublicURL),
	})
}

// notifyReply tells the author of comment parent on t that author replied.
func (s *Store) notifyReply(ctx context.Context, t Target, to, parent uuid.UUID, author dbq.User, body string) {
	r, ok := s.wants(ctx, to, "notify_comments")
	if !ok || !s.due(ctx, to, "replies:"+parent.String()) {
		return
	}
	link := s.PublicURL + "/" + t.Kind.table() + "/" + t.ID.String()
	if runes := []rune(body); len(runes) > 300 {
		body = string(runes[:300]) + " …"
	}
	var subject, text string
	switch r.locale {
	case "fr":
		subject = fmt.Sprintf("%s a répondu à ton commentaire sur « %s »", author.DisplayName, t.Title)
		text = fmt.Sprintf("Bonjour\n\n%s (@%s) a répondu à ton commentaire sur « %s » :\n\n%s\n\n%s\n\n"+
			"Les autres réponses des 15 prochaines minutes s'y trouvent aussi, sans e-mail supplémentaire.\n"+
			"Régler les notifications : %s/account\n", author.DisplayName, author.Username, t.Title, body, link, s.PublicURL)
	case "it":
		subject = fmt.Sprintf("%s ha risposto al tuo commento su «%s»", author.DisplayName, t.Title)
		text = fmt.Sprintf("Ciao\n\n%s (@%s) ha risposto al tuo commento su «%s»:\n\n%s\n\n%s\n\n"+
			"Le altre risposte dei prossimi 15 minuti le trovi lì, senza un'altra e-mail.\n"+
			"Impostazioni delle notifiche: %s/account\n", author.DisplayName, author.Username, t.Title, body, link, s.PublicURL)
	case "de":
		subject = fmt.Sprintf("%s hat auf deinen Kommentar zu «%s» geantwortet", author.DisplayName, t.Title)
		text = fmt.Sprintf("Hallo\n\n%s (@%s) hat auf deinen Kommentar zu «%s» geantwortet:\n\n%s\n\n%s\n\n"+
			"Weitere Antworten der nächsten 15 Minuten siehst du dort, ohne eigene E-Mail.\n"+
			"Benachrichtigungen einstellen: %s/account\n", author.DisplayName, author.Username, t.Title, body, link, s.PublicURL)
	default:
		subject = fmt.Sprintf("%s replied to your comment on “%s”", author.DisplayName, t.Title)
		text = fmt.Sprintf("Hi\n\n%s (@%s) replied to your comment on “%s”:\n\n%s\n\n%s\n\n"+
			"Further replies in the next 15 minutes are there too, without another e-mail.\n"+
			"Notification settings: %s/account\n", author.DisplayName, author.Username, t.Title, body, link, s.PublicURL)
	}
	s.send(ctx, mailer.Message{To: r.email, Subject: subject, Text: text})
}

func (s *Store) notifyFollow(ctx context.Context, follower dbq.User, followed uuid.UUID) {
	r, ok := s.wants(ctx, followed, "notify_follows")
	if !ok || !s.due(ctx, followed, "follows") {
		return
	}
	switch r.locale {
	case "fr":
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s te suit désormais", follower.DisplayName),
			Text: fmt.Sprintf("Bonjour\n\n%s (@%s) te suit désormais sur Alvyo et voit tes randonnées publiques "+
				"sous « Actualités ».\n\nRégler les notifications : %s/account\n", follower.DisplayName, follower.Username, s.PublicURL),
		})
		return
	case "it":
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s ora ti segue", follower.DisplayName),
			Text: fmt.Sprintf("Ciao\n\n%s (@%s) ora ti segue su Alvyo e vede le tue escursioni pubbliche "+
				"in «Novità».\n\nImpostazioni delle notifiche: %s/account\n", follower.DisplayName, follower.Username, s.PublicURL),
		})
		return
	case "de":
		s.send(ctx, mailer.Message{
			To:      r.email,
			Subject: fmt.Sprintf("%s folgt dir jetzt", follower.DisplayName),
			Text: fmt.Sprintf("Hallo\n\n%s (@%s) folgt dir jetzt auf Alvyo und sieht deine öffentlichen Touren "+
				"unter «Neuigkeiten».\n\nBenachrichtigungen einstellen: %s/account\n", follower.DisplayName, follower.Username, s.PublicURL),
		})
		return
	}
	s.send(ctx, mailer.Message{
		To:      r.email,
		Subject: fmt.Sprintf("%s now follows you", follower.DisplayName),
		Text: fmt.Sprintf("Hi\n\n%s (@%s) now follows you on Alvyo and sees your public hikes "+
			"under “News”.\n\nNotification settings: %s/account\n", follower.DisplayName, follower.Username, s.PublicURL),
	})
}
