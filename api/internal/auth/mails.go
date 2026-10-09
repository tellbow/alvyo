package auth

import (
	"fmt"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

func verificationMail(u dbq.User, link string) mailer.Message {
	switch u.Locale {
	case "fr":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo : confirmer ton adresse e-mail",
			Text: fmt.Sprintf("Bonjour %s\n\nMerci de confirmer ton adresse e-mail avec ce lien (valable 48 heures) :\n\n%s\n\n"+
				"Si tu n'as pas créé de compte Alvyo, tu peux ignorer cet e-mail.\n", u.DisplayName, link),
		}
	case "it":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: conferma il tuo indirizzo e-mail",
			Text: fmt.Sprintf("Ciao %s\n\nConferma il tuo indirizzo e-mail con questo link (valido 48 ore):\n\n%s\n\n"+
				"Se non hai creato un account Alvyo, puoi ignorare questa e-mail.\n", u.DisplayName, link),
		}
	case "de":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: E-Mail-Adresse bestätigen",
			Text: fmt.Sprintf("Hallo %s\n\nBitte bestätige deine E-Mail-Adresse mit diesem Link (gültig 48 Stunden):\n\n%s\n\n"+
				"Falls du kein Konto bei Alvyo erstellt hast, kannst du diese E-Mail ignorieren.\n", u.DisplayName, link),
		}
	}
	return mailer.Message{
		To:      u.Email,
		Subject: "Alvyo: confirm your e-mail address",
		Text: fmt.Sprintf("Hi %s\n\nPlease confirm your e-mail address with this link (valid for 48 hours):\n\n%s\n\n"+
			"If you did not create an Alvyo account, you can ignore this e-mail.\n", u.DisplayName, link),
	}
}

func resetMail(u dbq.User, link string) mailer.Message {
	switch u.Locale {
	case "fr":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo : réinitialiser ton mot de passe",
			Text: fmt.Sprintf("Bonjour %s\n\nAvec ce lien, tu peux définir un nouveau mot de passe (valable 1 heure) :\n\n%s\n\n"+
				"Les passkeys, les connexions avec Google ou Apple et les jetons d'accès sont supprimés ; ajoute-les de nouveau ensuite.\n\nSi tu n'as rien demandé, tu peux ignorer cet e-mail ; ton mot de passe reste inchangé.\n", u.DisplayName, link),
		}
	case "it":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: reimposta la password",
			Text: fmt.Sprintf("Ciao %s\n\nCon questo link puoi impostare una nuova password (valido 1 ora):\n\n%s\n\n"+
				"Passkey, accessi con Google o Apple e token di accesso vengono rimossi; aggiungili di nuovo dopo.\n\nSe non l'hai richiesto, puoi ignorare questa e-mail; la tua password resta invariata.\n", u.DisplayName, link),
		}
	case "de":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: Passwort zurücksetzen",
			Text: fmt.Sprintf("Hallo %s\n\nMit diesem Link kannst du ein neues Passwort setzen (gültig 1 Stunde):\n\n%s\n\n"+
				"Passkeys, Anmeldungen mit Google oder Apple und Zugriffstoken werden dabei entfernt; füge sie danach wieder hinzu.\n\nFalls du das nicht angefordert hast, kannst du diese E-Mail ignorieren; dein Passwort bleibt unverändert.\n", u.DisplayName, link),
		}
	}
	return mailer.Message{
		To:      u.Email,
		Subject: "Alvyo: reset your password",
		Text: fmt.Sprintf("Hi %s\n\nUse this link to set a new password (valid for 1 hour):\n\n%s\n\n"+
			"Passkeys, sign-ins with Google or Apple and access tokens are removed; add them again afterwards.\n\nIf you did not request this, you can ignore this e-mail; your password stays unchanged.\n", u.DisplayName, link),
	}
}

// accountExistsMail answers a signup with an address that has a confirmed
// account: no new account, but how to get into the one there is.
func accountExistsMail(u dbq.User, login, forgot string) mailer.Message {
	switch u.Locale {
	case "fr":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo : tu as déjà un compte",
			Text: fmt.Sprintf("Bonjour %s\n\nQuelqu'un (sans doute toi) a voulu créer un compte Alvyo avec cette adresse. Tu en as déjà un : %s (nom d'utilisateur %s).\n\n"+
				"Mot de passe oublié ? %s\n\nSi ce n'était pas toi, tu peux ignorer cet e-mail.\n", u.DisplayName, login, u.Username, forgot),
		}
	case "it":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: hai già un account",
			Text: fmt.Sprintf("Ciao %s\n\nQualcuno (probabilmente tu) ha voluto creare un account Alvyo con questo indirizzo. Ne hai già uno: %s (nome utente %s).\n\n"+
				"Password dimenticata? %s\n\nSe non sei stato tu, puoi ignorare questa e-mail.\n", u.DisplayName, login, u.Username, forgot),
		}
	case "de":
		return mailer.Message{
			To:      u.Email,
			Subject: "Alvyo: Du hast schon ein Konto",
			Text: fmt.Sprintf("Hallo %s\n\nJemand (wohl du) wollte mit dieser Adresse ein Alvyo-Konto eröffnen. Du hast schon eines: %s (Benutzername %s).\n\n"+
				"Passwort vergessen? %s\n\nFalls das nicht du warst, kannst du diese E-Mail ignorieren.\n", u.DisplayName, login, u.Username, forgot),
		}
	}
	return mailer.Message{
		To:      u.Email,
		Subject: "Alvyo: you already have an account",
		Text: fmt.Sprintf("Hi %s\n\nSomeone (probably you) tried to create an Alvyo account with this address. You already have one: %s (username %s).\n\n"+
			"Forgot your password? %s\n\nIf this was not you, you can ignore this e-mail.\n", u.DisplayName, login, u.Username, forgot),
	}
}
