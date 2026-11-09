# Écrans

Une fiche par écran : la méthode du modèle, les paramètres, les erreurs. Les routes et noms de contrôleurs sont des propositions ; les textes, l'ordre des questions et le découpage en étapes viennent des documents de conception (privés).

Les écrans d'authentification (lien magique, passkey, codes de secours, déconnexion) existent déjà. Les accueils par rôle existent, vides : `Declarant::HomeController`, `Analyst::HomeController`, `Admin::HomeController`.

Ce que le modèle ne fournit pas encore est listé à la fin : un écran qui en dépend attend la méthode, il ne la remplace pas dans son contrôleur.

## Déclarant

### Mes RETEX (accueil, `/`)

- Rôles : `:declarant, :analyst, :admin`.
- Données : `Report.owned_by(Current.user)`, brouillons compris. Seuls les rapports confidentiels dont le lien vit encore y figurent : un rapport décidé, ou soumis depuis plus de 60 jours, disparaît de la liste. Le dire à l'écran, c'est voulu.
- Par rapport : `event_type`, `status`, `submitted_on` (un mois, l'afficher comme tel : « novembre 2026 »), `open_draft?` (reprendre), `awaiting_clarification?` (une question attend), `draft_expires_on` pour un brouillon.
- Tri : aucune date précise n'existe, et il ne faut pas en ajouter. Brouillons d'abord, puis `submitted_on` décroissant.

### Commencer un RETEX

- `POST` vers une action qui appelle `Report.start_draft!(mode:, user:)`.
- Confidentiel : connecté, `user: Current.user`. Redirection vers la première étape.
- Anonyme : sans compte, `user: nil`, même si quelqu'un est connecté. La méthode renvoie `[report, token]` : le jeton va dans le cookie chiffré `draft_token` (voir [Contrôleurs](controleurs.md#secrets-montrés-une-fois)). Le contrôleur est ouvert sans connexion et s'ajoute aux exemptions de `default_deny_spec.rb`.
- Point d'entrée : un écran « Déclarer un RETEX », ouvert sans connexion, propose les deux modes. Confidentiel : connexion si besoin, puis brouillon. Anonyme : brouillon tout de suite, sans compte. La page de connexion y renvoie. Une personne connectée voit aussi les deux choix.

### Formulaire en étapes

- Retrouver le brouillon : `Report.owned_by(Current.user).find(params[:id])` en confidentiel ; `Report.find_draft_by_token(cookies.encrypted[:draft_token])` en anonyme.
- Afficher les champs de `report.taxonomy_version.fields`, groupés par `group`, dans l'ordre de `position`, avec `field.options` (`code`, `label`, `definition`). Composants : `components/choice_cards` (single, multi), `components/text_field`, `components/steps`.
- Enregistrer chaque étape : `report.save_draft!(report_params)` avec le `params.expect` de [Contrôleurs](controleurs.md#paramètres). Chaque enregistrement repousse l'expiration de 30 jours.
- **Attention :** `answers` et `free_text_answers` sont remplacés en entier à chaque enregistrement, et les champs de `answers` se répartissent sur plusieurs étapes. Une étape qui ne poste que ses propres champs efface ceux des autres. Tant que le modèle ne fusionne pas par étape (voir la fin de cette page), chaque étape doit renvoyer tout le hash, en champs cachés pour les réponses des autres étapes.
- Récit : `narrative_attributes[raw_text]`, 20 000 caractères au plus ; chaque débrief et chaque réponse libre : 5 000.
- Victimes : `casualties_attributes`, une entrée par personne, `_destroy` pour en retirer une.
- Erreurs : `RecordInvalid` → 422 avec `report.errors` (les codes de `answers` sont dans les détails de l'erreur : `"<champ>.<erreur>"`) ; `InvalidTransition` (brouillon expiré ou déjà soumis) → redirection vers Mes RETEX avec un message ; `RecordNotFound` → 404.

### Récapitulatif et envoi

- `GET` : le brouillon relu, sans écrire.
- `POST` : `report.submit!`.
  - Confidentiel : renvoie `nil`. Redirection vers Mes RETEX.
  - Anonyme : renvoie le **code de suivi** en clair, une seule fois. L'afficher dans la réponse même, `Cache-Control: no-store`, avec la consigne de le noter ; supprimer le cookie `draft_token`.
- Erreur : `InvalidTransition` (brouillon expiré, déjà soumis, lien coupé) → redirection avec un message.

### Suivre un rapport soumis

- Confidentiel : `Report.owned_by(Current.user).find(params[:id])`.
- Anonyme : un formulaire demande le code de suivi (`POST`, champ `tracking_code`, `rate_limit` par `IpFingerprint.for(request)`), puis `Report.find_by_tracking_code(params[:tracking_code])`. Code faux → même message que « introuvable ». La page affichée porte `Cache-Control: no-store` et garde le code dans un champ caché des formulaires qui suivent (réponse, modification) : il n'est stocké nulle part ailleurs.
- Afficher : `status`, `report.clarifications` (dans l'ordre, `author` et `body`), le formulaire de réponse si `awaiting_clarification?`, le lien de modification si le rapport est encore modifiable.
- Le rapport devient introuvable pour le déclarant : en confidentiel à la décision ou 60 jours après la soumission (le lien est coupé), en anonyme à la décision ou à la purge des 180 jours (le code de suivi est effacé). La page de saisie du code doit le dire, pour qu'un code « qui ne marche plus » ne passe pas pour une erreur.

### Répondre à une question

- `report.answer_clarification!(body, user: Current.user)` en confidentiel, `report.answer_clarification!(body, tracking_code: params[:tracking_code])` en anonyme.
- Le modèle exige seulement qu'une question de l'analyste existe dans le fil : le déclarant peut répondre plusieurs fois de suite. Afficher le formulaire selon `awaiting_clarification?` reste le choix de l'écran.
- Erreurs : `RecordInvalid` (corps vide) → 422 ; `NotAllowed` → 404 ; `InvalidTransition` (aucune question de l'analyste dans le fil, rapport décidé) → redirection avec un message.

### Modifier après envoi

- Possible tant qu'aucun analyste n'a pris le rapport en charge (bouton, question ou décision) et au plus 60 jours après la soumission.
- Même formulaire que le brouillon, même `params.expect`. `report.edit_submitted!(report_params, user: Current.user)` ou `tracking_code: params[:tracking_code]`.
- Si le récit ou le débriefing change, l'analyse repart de zéro : le dire au déclarant avant l'envoi. Un formulaire renvoyé sans changement n'écrit rien.
- `rate_limit` obligatoire : chaque modification du texte relance le LLM.
- Erreurs : `RecordInvalid` → 422 ; `NotAllowed` → 404 ; `InvalidTransition` (pris en charge entre-temps, fenêtre fermée, rapport décidé) → redirection avec un message.

## Analyste

### File des rapports (`/analyst`)

- Rôles : `:analyst, :admin`.
- Données : `Report.where(status: Report::UNDER_ANALYSIS_STATUSES)` ; les décidés avec `Report.decided`.
- Par rapport : `event_type`, `discipline`, `severity`, `submitted_on` (mois), `status`, `taken_in_charge?`, `awaiting_clarification?`, statut de la dernière analyse (`failed` : à coder à la main), `raw_content_purged?` (180 jours passés : plus de récit).
- Pas de tri par date de soumission précise : elle n'existe pas.

### Fiche d'un rapport

- `Report.find(params[:id])`. Ouvrir la fiche n'écrit rien : pas de trace de consultation.
- Afficher : `report.narrative` (récit, cinq débriefs, `free_text_answers`), les colonnes et `answers` avec les libellés de la taxonomie du rapport, `report.casualties`, `report.analyses` (pour chaque champ, `value` et `excerpt` ; `value` à `nil` veut dire « non renseigné dans le récit »), `report.clarifications`, le mode (confidentiel ou anonyme : un anonyme ne reçoit pas de mail, il doit revenir avec son code).
- Ne jamais afficher ni chercher qui est l'auteur. `ReportOwnership` n'a rien à faire dans une vue de l'équipe.
- Actions, chacune un formulaire en `POST` vers une action qui appelle une méthode :
  - Prendre en charge : `report.take_charge!(Current.user)`. Ferme la modification par le déclarant. Idempotent.
  - Poser une question : `report.ask_clarification!(Current.user, body)`. Aucun mail sur le moment ; le déclarant confidentiel reçoit un mail neutre le lundi suivant, seulement si le lien vit encore et si son compte est actif. Après les 60 jours, le déclarant ne retrouve plus le rapport et ne peut plus répondre. L'écran le rappelle par une mention générale (« en mode confidentiel, le déclarant ne peut répondre que dans les 60 jours qui suivent l'envoi »), jamais par un état propre au rapport, qui donnerait le jour d'envoi.
  - Valider : `report.validate!(Current.user)`, seulement depuis `in_validation`.
  - Rejeter : `report.reject!(Current.user)`, depuis tout statut sous analyse.
- Valider et rejeter suppriment le récit, le fil et le lien vers l'auteur, sans retour possible : demander confirmation (`data-turbo-confirm`, ou le contrôleur Stimulus `confirm` pour un formulaire sans Turbo).
- Erreurs : `NotAllowed` (compte désactivé entre-temps, cas rare : sa session est déjà refusée) → 403, voir [Contrôleurs](controleurs.md#erreurs-et-codes-http) ; `InvalidTransition` → redirection vers la fiche avec un message ; `RecordInvalid` (question vide) → 422.

## Administration (`/admin`)

- Rôle : `:admin`.
- Existe déjà : réinitialiser les passkeys d'un membre de l'équipe (`Admin::PasskeyResetsController`, affiche le code d'enrôlement une fois) et désactiver un compte (`Admin::DeactivationsController`).
- À construire : donner un code d'enrôlement à un nouveau membre de l'équipe (`user.issue_enrollment_code!(by: Current.user)`, code montré une fois, `no-store`), publier une version de taxonomie (`taxonomy_version.publish!` ; l'import se fait en console avec `TaxonomyVersion.import!`).

## Ce que le modèle ne fournit pas encore

À trancher avec Hugo avant l'écran concerné.

1. **Le codage par l'analyste.** Aucune méthode n'enregistre les corrections de l'analyste sur les propositions (`Analysis#modifications`, statut `reviewed`), ni le codage à la main après une analyse `failed`, ni la mise à jour des colonnes et des `answers` d'un rapport soumis. Bloque la fiche analyste au-delà de la lecture. Décidé : le rapport porte les codes définitifs, que l'analyste corrige après la prise en charge (méthode à venir) ; les vides sont pré-remplis par la proposition du LLM ; `Analysis` reste la photo des propositions, pour mesurer la qualité du LLM.
2. **Le récit anonymisé.** Absent du schéma : à la validation, il ne reste aujourd'hui que les réponses codées. Décidé : l'analyste rédige un texte anonymisé, exigé par `validate!` (sauf récit déjà purgé) et seul texte conservé après la validation. Le LLM le pré-remplira peut-être, selon la calibration ; l'écran prévoit un champ pré-rempli ou vide.
3. **Les valeurs du formulaire.** Un formulaire envoie des chaînes : un champ `integer` arrive en `"3"`, refusé (`not_an_integer`) ; un choix laissé vide arrive en `""`, refusé (`invalid_option`). Il faut convertir et nettoyer dans le modèle avant la validation.
4. **« Encore modifiable ? »** Pas de prédicat pour afficher ou non le lien de modification. La condition est dans `edit_submitted!` ; une méthode publique du modèle doit la porter, pas la vue.
5. **Un brouillon complet.** `submit!` accepte un brouillon vide. Décidé : seuls le type d'événement et un récit non vide seront obligatoires ; `submit!` refusera sinon, avec une erreur par champ (méthode à venir).
6. **Le nombre de victimes.** Aucune limite aujourd'hui. Décidé : trois au plus, le modèle refusera la quatrième ; l'écran peut masquer « ajouter une victime » à trois (validation à venir).
7. **La fin d'adhésion** déclarée par le moniteur : aucune méthode.
8. **Changer un rôle**, nommer un analyste : aucune méthode (la règle des deux admins est déjà dans la validation de `User`).
9. **Les statistiques** : aucune requête.
10. **L'enregistrement par étape.** `save_draft!` remplace `answers` et `free_text_answers` en entier ; une fusion par étape dans le modèle éviterait de renvoyer tout le hash à chaque étape.
11. **« Le déclarant peut-il encore répondre ? »** Volontairement sans réponse par rapport : en confidentiel, la réponse bascule le jour exact de la coupure, soit 60 jours après la soumission, et un écran de l'équipe qui l'afficherait donnerait le jour d'envoi. L'écran analyste affiche une mention générale, la même pour tous les rapports, et ne lit jamais `ReportOwnership`.
