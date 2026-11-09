# Contrôleurs

## La forme d'une action

Une action lit les paramètres, autorise, appelle **une** méthode du modèle, puis rend ou redirige. Pas de logique métier, pas de transaction, pas de deuxième écriture : si une action a besoin de deux écritures, il manque une méthode au modèle (le dire plutôt que de l'écrire dans le contrôleur).

```ruby
class Declarant::ClarificationsController < ApplicationController
  require_role :declarant, :analyst, :admin

  def create
    report = Report.owned_by(Current.user).find(params[:report_id])
    report.answer_clarification!(params.expect(clarification: [ :body ])[:body], user: Current.user)
    redirect_to declarant_report_path(report), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @report, @clarification = report, error.record
    render "declarant/reports/show", status: :unprocessable_entity
  end
end
```

Un GET n'écrit jamais rien et ne lance aucun calcul : ouvrir la fiche d'un rapport ne le prend pas en charge, il faut un bouton (un formulaire en POST).

## Authentification et rôles

- Tout contrôleur est fermé par défaut : connexion obligatoire (`Authentication`), passkey vérifiée pour l'équipe (`Authorization`).
- Chaque contrôleur déclare `require_role` avec les rôles qu'il sert. `spec/requests/default_deny_spec.rb` échoue sinon. Tout compte connecté peut déclarer : un écran de déclarant sert `:declarant, :analyst, :admin`.
- Un écran ouvert sans compte (mode anonyme) déclare `allow_unauthenticated_access`, sans `require_role` (il n'y a pas d'utilisateur à qui demander un rôle), et s'ajoute aux exemptions de `default_deny_spec.rb` avec sa raison.
- Un refus de rôle rend `errors/forbidden` en 403. Cette page n'existe qu'en HTML : à étendre avant un premier écran en Turbo Stream.

## Retrouver un rapport

L'autorisation passe **avant** toute lecture d'état, pour qu'un inconnu n'apprenne rien sur un rapport.

| Qui | Comment |
| --- | --- |
| Déclarant confidentiel | `Report.owned_by(Current.user).find(id)` : la portée est l'autorisation. Un rapport d'un autre, ou dont le lien est coupé, donne 404. |
| Déclarant anonyme, brouillon | `Report.find_draft_by_token(cookies.encrypted[:draft_token])`, ressource au singulier, sans identifiant dans l'URL. |
| Déclarant anonyme, rapport soumis | `Report.find_by_tracking_code(params[:tracking_code])`, jamais par identifiant. |
| Équipe | `Report.find(id)`, une fois `require_role :analyst, :admin` passé. |

Puis ne transmettre au modèle que l'identité qui correspond au mode du rapport : `user: Current.user` en confidentiel, `tracking_code:` en anonyme, jamais les deux. Un compte connecté qui suit un rapport anonyme passe `user: nil`.

## Erreurs et codes HTTP

| Exception | Réponse |
| --- | --- |
| `ActiveRecord::RecordInvalid` | Réafficher le formulaire en 422 (`:unprocessable_entity`) avec `error.record.errors`. Turbo exige 422 pour afficher un formulaire refusé. |
| `ActiveRecord::RecordNotFound` | 404 (comportement par défaut de Rails, ne pas l'intercepter). |
| `Report::NotAllowed` | Côté déclarant : 404, comme un rapport inexistant, car un refus ne doit pas confirmer qu'un rapport existe. Côté équipe (compte qui n'est plus actif) : 403. |
| `Report::InvalidTransition` | Redirection 303 vers la fiche du rapport avec un message (le rapport a changé d'état entre l'affichage et l'envoi : brouillon expiré, rapport pris en charge entre-temps…). |
| `ArgumentError` venu du modèle (« not draft content ») | Ne pas l'intercepter : c'est un `permit` trop large, une erreur de programmation. |
| `User::PasskeyResetNotAllowed`, `User::DeactivationNotAllowed`, `User::TooFewAdmins` | Redirection 303 avec un message, comme dans `Admin::DeactivationsController`. |
| Limite de débit atteinte | 429 (`:too_many_requests`) avec un message, voir `MagicLinksController`. |

Toute redirection après un POST, PATCH ou DELETE prend `status: :see_other`.

## Paramètres

- `params.expect` (ou `require`/`permit`) avec la liste exacte des clés. Les méthodes `save_draft!` et `edit_submitted!` refusent toute clé hors du contenu du formulaire (`Report::DRAFT_ATTRIBUTES`, `DRAFT_NARRATIVE_ATTRIBUTES`, `DRAFT_CASUALTY_ATTRIBUTES`).
- Les hash libres se déclarent avec `{}`, sinon ils disparaissent **sans erreur** :

```ruby
params.expect(report: [
  :event_type, :discipline, :environment, :cause, :severity,
  answers: {},
  narrative_attributes: [ :raw_text, *Narrative::DEBRIEF_FIELDS, free_text_answers: {} ],
  casualties_attributes: [ [ :id, :severity, :_destroy, answers: {} ] ]
])
```

- Les noms de paramètres sensibles sont filtrés des logs (`config/initializers/filter_parameter_logging.rb`). Un nouveau paramètre qui porte du texte libre ou un secret s'y ajoute.

## Secrets montrés une fois

Le jeton de brouillon anonyme, le code de suivi, les codes de secours et le code d'enrôlement ne sont stockés qu'en empreinte : la méthode du modèle les renvoie en clair une seule fois.

- Les afficher dans la réponse même de l'action qui les crée, avec `response.headers["Cache-Control"] = "no-store"` (voir `Admin::PasskeyResetsController`). Jamais dans le flash, l'URL ou un paramètre de redirection.
- `no-store` n'arrête pas le cache de Turbo : ajouter aussi `<meta name="turbo-cache-control" content="no-cache">` dans le `<head>` de ces pages (`content_for :head`), sinon le code réapparaît au retour arrière.
- Le jeton de brouillon va dans un cookie chiffré, `httponly`, `same_site: :lax`, qui expire avec le brouillon, et qui est supprimé à la soumission.
- Le code de suivi ne passe jamais dans une URL (logs, historique du navigateur) : il est saisi dans un formulaire en POST, sous le nom `tracking_code`.

## Limites de débit

Toute action qui envoie un mail, appelle le LLM ou vérifie un secret porte un `rate_limit` :

- clé : `Current.user.id` pour une action liée à un compte ; `IpFingerprint.for(request)` pour toute action liée à un rapport anonyme, **même si la personne est connectée** (sinon le cache des limites, en base, associerait un compte à une activité anonyme). Jamais `request.remote_ip` : aucune IP n'est stockée ;
- `store: Rails.configuration.x.rate_limit_store || cache_store`, comme les contrôleurs existants ;
- obligatoire sur la modification après envoi (chaque modification du texte relance le LLM) et sur la saisie du code de suivi.

## Ce qu'un contrôleur ne fait jamais

- Écrire un `AccessLog` ou un `AuditEvent` : les méthodes du modèle s'en chargent.
- Journaliser quoi que ce soit sur un rapport (identifiant, contenu, mode) ou sur un utilisateur.
- Passer un rapport, un utilisateur ou un texte à un job ou un mail : le modèle décide de ce qui part.
- Lire `ENV` (seulement dans `config/`).
- Changer un statut, une date de coupure ou d'expiration.
