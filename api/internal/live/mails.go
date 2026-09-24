package live

import (
	"fmt"
	"time"

	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/swiss/lv95"
)

// zurich: times in the e-mails are Swiss.
var zurich = func() *time.Location {
	loc, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		return time.UTC
	}
	return loc
}()

func clock(t time.Time) string { return t.In(zurich).Format("02.01.2006 15:04") }

// where writes a position for a rescue: WGS84 and Swiss coordinates.
func where(p *Position) string {
	if p == nil {
		return "–"
	}
	e, n := lv95.FromWGS84(p.Lon, p.Lat)
	return fmt.Sprintf("%.5f, %.5f (WGS84) / %.0f, %.0f (LV95), %s", p.Lat, p.Lon, e, n, clock(p.At))
}

// The e-mails are in the hiker's language; the contacts are theirs.

func startMail(h Hiker, to, title string, end time.Time, link, email string) mailer.Message {
	var subject, text string
	switch h.Locale {
	case "fr":
		subject = fmt.Sprintf("%s partage sa position : « %s »", h.DisplayName, title)
		text = fmt.Sprintf("Bonjour %s\n\n%s part en randonnée « %s » et partage sa position avec toi jusqu'à la fin :\n\n%s\n\n"+
			"Fin prévue : %s. Si la randonnée n'est pas terminée 30 minutes plus tard, tu reçois un e-mail avec la dernière position.\n",
			to, h.DisplayName, title, link, clock(end))
	case "it":
		subject = fmt.Sprintf("%s condivide la sua posizione: «%s»", h.DisplayName, title)
		text = fmt.Sprintf("Ciao %s\n\n%s parte per l'escursione «%s» e condivide con te la sua posizione fino alla fine:\n\n%s\n\n"+
			"Fine prevista: %s. Se l'escursione non è terminata 30 minuti dopo, ricevi un'e-mail con l'ultima posizione.\n",
			to, h.DisplayName, title, link, clock(end))
	case "en":
		subject = fmt.Sprintf("%s shares their position: “%s”", h.DisplayName, title)
		text = fmt.Sprintf("Hi %s\n\n%s is setting off on “%s” and shares their position with you until the end:\n\n%s\n\n"+
			"Expected end: %s. If the hike has not ended 30 minutes later, you get an e-mail with the last position.\n",
			to, h.DisplayName, title, link, clock(end))
	default:
		subject = fmt.Sprintf("%s teilt den Standort: «%s»", h.DisplayName, title)
		text = fmt.Sprintf("Hallo %s\n\n%s ist auf der Wanderung «%s» und teilt mit dir den Standort bis zum Ende:\n\n%s\n\n"+
			"Geplantes Ende: %s. Ist die Wanderung 30 Minuten danach nicht beendet, bekommst du eine E-Mail mit dem letzten Standort.\n",
			to, h.DisplayName, title, link, clock(end))
	}
	return mailer.Message{To: email, Subject: subject, Text: text}
}

func overdueMail(h Hiker, to, title string, end time.Time, last *Position, link, email string) mailer.Message {
	var subject, text string
	switch h.Locale {
	case "fr":
		subject = fmt.Sprintf("%s n'a pas terminé « %s »", h.DisplayName, title)
		text = fmt.Sprintf("Bonjour %s\n\nLa randonnée « %s » de %s devait se terminer le %s et n'est pas encore terminée.\n\n"+
			"Dernière position : %s\n%s\n\nEssaie de le/la joindre. En cas d'urgence en montagne : Rega 1414, ou 112.\n",
			to, title, h.DisplayName, clock(end), where(last), link)
	case "it":
		subject = fmt.Sprintf("%s non ha terminato «%s»", h.DisplayName, title)
		text = fmt.Sprintf("Ciao %s\n\nL'escursione «%s» di %s doveva terminare il %s e non è ancora terminata.\n\n"+
			"Ultima posizione: %s\n%s\n\nProva a contattarlo/a. In caso di emergenza in montagna: Rega 1414, o 112.\n",
			to, title, h.DisplayName, clock(end), where(last), link)
	case "en":
		subject = fmt.Sprintf("%s has not ended “%s”", h.DisplayName, title)
		text = fmt.Sprintf("Hi %s\n\n%s's hike “%s” was expected to end at %s and has not ended yet.\n\n"+
			"Last position: %s\n%s\n\nTry to reach them. In a mountain emergency: Rega 1414, or 112.\n",
			to, h.DisplayName, title, clock(end), where(last), link)
	default:
		subject = fmt.Sprintf("%s hat «%s» nicht beendet", h.DisplayName, title)
		text = fmt.Sprintf("Hallo %s\n\nDie Wanderung «%s» von %s sollte am %s zu Ende sein und ist noch nicht beendet.\n\n"+
			"Letzter Standort: %s\n%s\n\nVersuche, sie oder ihn zu erreichen. Im Notfall in den Bergen: Rega 1414, oder 112.\n",
			to, title, h.DisplayName, clock(end), where(last), link)
	}
	return mailer.Message{To: email, Subject: subject, Text: text}
}

func overdueSelfMail(h Hiker, title string, end time.Time, link string) mailer.Message {
	var subject, text string
	switch h.Locale {
	case "fr":
		subject = fmt.Sprintf("Tes contacts ont été avertis : « %s »", title)
		text = fmt.Sprintf("Ta randonnée « %s » devait se terminer le %s. Tes contacts ont reçu ta dernière position.\n"+
			"Si tout va bien, termine la randonnée dans l'app ou choisis « Plus tard ».\n\n%s\n", title, clock(end), link)
	case "it":
		subject = fmt.Sprintf("I tuoi contatti sono stati avvisati: «%s»", title)
		text = fmt.Sprintf("La tua escursione «%s» doveva terminare il %s. I tuoi contatti hanno ricevuto la tua ultima posizione.\n"+
			"Se va tutto bene, termina l'escursione nell'app o scegli «Più tardi».\n\n%s\n", title, clock(end), link)
	case "en":
		subject = fmt.Sprintf("Your contacts were alerted: “%s”", title)
		text = fmt.Sprintf("Your hike “%s” was expected to end at %s. Your contacts got your last position.\n"+
			"If all is well, end the hike in the app or choose “Later”.\n\n%s\n", title, clock(end), link)
	default:
		subject = fmt.Sprintf("Deine Kontakte wurden benachrichtigt: «%s»", title)
		text = fmt.Sprintf("Deine Wanderung «%s» sollte am %s zu Ende sein. Deine Kontakte haben deinen letzten Standort bekommen.\n"+
			"Ist alles in Ordnung, beende die Wanderung in der App oder wähle «Später».\n\n%s\n", title, clock(end), link)
	}
	return mailer.Message{To: h.Email, Subject: subject, Text: text}
}

// allClearMail: after an alert, the hike ended (end nil) or goes on until end.
func allClearMail(h Hiker, to, title string, end *time.Time, email string) mailer.Message {
	var subject, text string
	switch h.Locale {
	case "fr":
		subject = fmt.Sprintf("Tout va bien : %s, « %s »", h.DisplayName, title)
		text = fmt.Sprintf("Bonjour %s\n\n%s a terminé la randonnée « %s ».\n", to, h.DisplayName, title)
		if end != nil {
			text = fmt.Sprintf("Bonjour %s\n\n%s donne des nouvelles : « %s » se terminera vers %s.\n", to, h.DisplayName, title, clock(*end))
		}
	case "it":
		subject = fmt.Sprintf("Tutto bene: %s, «%s»", h.DisplayName, title)
		text = fmt.Sprintf("Ciao %s\n\n%s ha terminato l'escursione «%s».\n", to, h.DisplayName, title)
		if end != nil {
			text = fmt.Sprintf("Ciao %s\n\n%s si è fatto/a vivo/a: «%s» terminerà verso le %s.\n", to, h.DisplayName, title, clock(*end))
		}
	case "en":
		subject = fmt.Sprintf("All is well: %s, “%s”", h.DisplayName, title)
		text = fmt.Sprintf("Hi %s\n\n%s has ended the hike “%s”.\n", to, h.DisplayName, title)
		if end != nil {
			text = fmt.Sprintf("Hi %s\n\n%s checked in: “%s” will end around %s.\n", to, h.DisplayName, title, clock(*end))
		}
	default:
		subject = fmt.Sprintf("Alles in Ordnung: %s, «%s»", h.DisplayName, title)
		text = fmt.Sprintf("Hallo %s\n\n%s hat die Wanderung «%s» beendet.\n", to, h.DisplayName, title)
		if end != nil {
			text = fmt.Sprintf("Hallo %s\n\n%s hat sich gemeldet: «%s» dauert bis etwa %s.\n", to, h.DisplayName, title, clock(*end))
		}
	}
	return mailer.Message{To: email, Subject: subject, Text: text}
}
