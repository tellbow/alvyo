package reminders

import (
	"fmt"
	"strings"
	"time"

	"github.com/tellbow/alvyo/api/internal/mailer"
)

// stageName is a stage's title, or «Etappe 3» without one.
func stageName(locale string, n int, title string) string {
	if title != "" {
		return fmt.Sprintf("%d. %s", n, title)
	}
	switch locale {
	case "fr":
		return fmt.Sprintf("Étape %d", n)
	case "it":
		return fmt.Sprintf("Tappa %d", n)
	case "en":
		return fmt.Sprintf("Stage %d", n)
	}
	return fmt.Sprintf("Etappe %d", n)
}

func day(t time.Time) string { return t.Format("02.01.2006") }

// reminderMail is a reminder in the reader's language; the link opens the
// journey, where reminders are turned off.
func reminderMail(d due, link string) mailer.Message {
	list := "- " + strings.Join(d.unbooked, "\n- ")
	var subject, text string
	switch d.locale {
	case "fr":
		off := "Pour ne plus recevoir ces rappels : « Rappels » sur la page du trek."
		switch d.kind {
		case "book":
			subject = fmt.Sprintf("« %s » dans trois semaines : réserver les nuits", d.title)
			text = fmt.Sprintf("Bonjour %s\n\n« %s » commence le %s. Ces nuits ne sont pas encore réservées :\n\n%s\n\n"+
				"Les cabanes affichent souvent complet des semaines à l'avance.\n\n%s\n\n%s\n", d.name, d.title, day(d.startOn), list, link, off)
		case "weather":
			subject = fmt.Sprintf("« %s » après-demain : la météo", d.title)
			text = fmt.Sprintf("Bonjour %s\n\n« %s » commence après-demain, le %s. La prévision de MétéoSuisse pour chaque étape :\n\n%s\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		default:
			subject = fmt.Sprintf("« %s » commence demain", d.title)
			text = fmt.Sprintf("Bonjour %s\n\n« %s » commence demain, le %s. Les cartes hors ligne et le trajet sont sur la page :\n\n%s\n\nBonne route !\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		}
	case "it":
		off := "Per non ricevere più questi promemoria: «Promemoria» sulla pagina del trekking."
		switch d.kind {
		case "book":
			subject = fmt.Sprintf("«%s» tra tre settimane: prenotare le notti", d.title)
			text = fmt.Sprintf("Ciao %s\n\n«%s» inizia il %s. Queste notti non sono ancora prenotate:\n\n%s\n\n"+
				"Le capanne sono spesso al completo settimane prima.\n\n%s\n\n%s\n", d.name, d.title, day(d.startOn), list, link, off)
		case "weather":
			subject = fmt.Sprintf("«%s» dopodomani: il meteo", d.title)
			text = fmt.Sprintf("Ciao %s\n\n«%s» inizia dopodomani, il %s. La previsione di MeteoSvizzera per ogni tappa:\n\n%s\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		default:
			subject = fmt.Sprintf("«%s» inizia domani", d.title)
			text = fmt.Sprintf("Ciao %s\n\n«%s» inizia domani, il %s. Le mappe offline e il viaggio sono sulla pagina:\n\n%s\n\nBuon cammino!\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		}
	case "en":
		off := "To stop these reminders: «Reminders» on the journey's page."
		switch d.kind {
		case "book":
			subject = fmt.Sprintf("“%s” in three weeks: book the nights", d.title)
			text = fmt.Sprintf("Hi %s\n\n“%s” starts on %s. These nights are not booked yet:\n\n%s\n\n"+
				"Huts are often full weeks ahead.\n\n%s\n\n%s\n", d.name, d.title, day(d.startOn), list, link, off)
		case "weather":
			subject = fmt.Sprintf("“%s” the day after tomorrow: the weather", d.title)
			text = fmt.Sprintf("Hi %s\n\n“%s” starts the day after tomorrow, on %s. MeteoSwiss's forecast for each stage:\n\n%s\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		default:
			subject = fmt.Sprintf("“%s” starts tomorrow", d.title)
			text = fmt.Sprintf("Hi %s\n\n“%s” starts tomorrow, on %s. Offline maps and the way there are on its page:\n\n%s\n\nHave a good hike!\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		}
	default:
		off := "Keine Erinnerungen mehr: «Erinnerungen» auf der Seite der Etappentour."
		switch d.kind {
		case "book":
			subject = fmt.Sprintf("«%s» in drei Wochen: Übernachtungen buchen", d.title)
			text = fmt.Sprintf("Hallo %s\n\n«%s» beginnt am %s. Diese Übernachtungen sind noch nicht gebucht:\n\n%s\n\n"+
				"Hütten sind oft Wochen im Voraus voll.\n\n%s\n\n%s\n", d.name, d.title, day(d.startOn), list, link, off)
		case "weather":
			subject = fmt.Sprintf("«%s» übermorgen: das Wetter", d.title)
			text = fmt.Sprintf("Hallo %s\n\n«%s» beginnt übermorgen, am %s. Die Prognose von MeteoSchweiz für jede Etappe:\n\n%s\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		default:
			subject = fmt.Sprintf("«%s» beginnt morgen", d.title)
			text = fmt.Sprintf("Hallo %s\n\n«%s» beginnt morgen, am %s. Offline-Karten und die Anreise findest du auf der Seite:\n\n%s\n\nGute Wanderung!\n\n%s\n",
				d.name, d.title, day(d.startOn), link, off)
		}
	}
	return mailer.Message{To: d.email, Subject: subject, Text: text}
}
