# Domaine

## Les modèles

| Modèle | Ce qu'il porte | À savoir |
| --- | --- | --- |
| `User` | Un compte : e-mail, rôle (`declarant`, `analyst`, `admin`), fin d'adhésion | E-mail chiffré (déterministe, retrouvable). Aucune date de connexion. Les comptes de l'équipe sont désactivés (`deactivate!`), jamais supprimés ; ceux des déclarants inutilisés sont purgés. |
| `Session` | Une connexion | Expire à la fin du mois suivant. Ni IP ni user agent. `passkey_verified`, `recovered` pour l'équipe. |
| `Passkey`, `RecoveryCode` | Second facteur de l'équipe | Déjà branchés sur leurs écrans. |
| `Report` | Le RETEX | Clé UUID, aucune date précise : seul `submitted_on` (le 1er du mois de soumission). Aucune clé vers `User`. Porte les **codes définitifs** (colonnes, `answers`) et `anonymized_text`, le récit anonymisé écrit par l'analyste (chiffré, non déterministe). |
| `Narrative` | Récit et cinq réponses de débriefing, réponses libres de la taxonomie | Tout est chiffré et supprimé à la décision. Un seul par rapport. |
| `Casualty` | Une personne blessée ou concernée | Gravité en colonne, le reste dans `answers` (taxonomie, portée `casualty`). Plusieurs par rapport. |
| `ReportOwnership` | **Le seul lien** entre un rapport et son auteur | `user_ref` chiffré, date de coupure. Supprimé à la décision ou à la coupure. |
| `Analysis` | Les propositions de l'extracteur (LLM) | Une par version de prompt. `proposals` : `{ code => { "value" => …, "excerpt" => "…" } }`, chiffré. `status` : `proposed` ou `failed`. C'est une photo de ce que le LLM a proposé : elle ne change pas quand l'analyste corrige. `Analysis.proposal_vs_validated` la compare, champ par champ, aux codes des rapports validés (qualité du LLM). |
| `Clarification` | Un message du fil entre analyste et déclarant | Corps chiffré, `author` (`analyst`, `declarant`), `position`. Supprimé à la décision. |
| `TaxonomyVersion`, `TaxonomyField`, `TaxonomyOption` | La taxonomie versionnée | Une version publiée est immuable. `TaxonomyVersion.current` est la dernière publiée. |
| `AccessLog` | Quel membre de l'équipe a agi sur quel rapport | Au mois près. Écrit par les méthodes du modèle, jamais par un contrôleur. |
| `AuditEvent` | Actions d'administration | Réinitialisation de passkeys, code d'enrôlement, désactivation, passkey enregistrée après un code de secours. |

### Où vont les réponses du formulaire

Chaque `TaxonomyField` a un `code`, un `group` (étape du formulaire : `context`, `event`, `consequences`, `casualty`, `factors`), un `kind` et une `scope` (`report` ou `casualty`).

- `discipline`, `environment`, `cause`, `severity` : **colonnes** de `Report` (filtres et statistiques). Ne pas les mettre aussi dans `answers`.
- Les autres champs `single`, `multi`, `integer` de portée `report` : `Report#answers` (`jsonb`), `{ code => valeur }`. `single` : une chaîne ; `multi` : une liste de chaînes sans doublon ; `integer` : un entier ≥ 0.
- Les champs `text` : `Narrative#free_text_answers`, chiffré, jamais dans `answers` (refusé).
- Portée `casualty` : `Casualty#severity` et `Casualty#answers`.

Les valeurs sont des **codes** d'options (`TaxonomyOption#code`) ; le libellé et la définition s'affichent, le code s'enregistre. Un rapport garde à vie la version de taxonomie de sa création (`taxonomy_version`, en lecture seule) : un brouillon commencé en v0 se termine en v0. Pour afficher un formulaire, lire les champs de **cette** version, pas de `TaxonomyVersion.current`.

## Cycle de vie d'un RETEX

```
draft ──submit!──▶ submitted ──▶ analyzing ──▶ in_validation ──validate!──▶ validated
                       ▲                                     └──reject!───▶ rejected
                       └── edit_submitted! (si le texte change)   (reject! aussi depuis submitted et analyzing)
```

Le statut ne change **que** par une méthode du cycle de vie ; un `update(status: …)` est refusé par une validation. « En attente de précisions » n'est pas un statut : `awaiting_clarification?` est vrai quand le dernier message du fil vient de l'analyste.

| Étape | Méthode | Effet |
| --- | --- | --- |
| Démarrer | `Report.start_draft!(mode:, user:)` | Crée le brouillon, valable 30 jours. Confidentiel : crée le `ReportOwnership`. Anonyme : renvoie un jeton en clair, une seule fois, pour le cookie. |
| Enregistrer | `report.save_draft!(attrs)` | Repousse l'expiration à aujourd'hui + 30 jours. Contenu du formulaire seulement. |
| Soumettre | `report.submit!` | `submitted_on` = 1er du mois, modifiable 60 jours, lien coupé à J+60. Anonyme : renvoie le **code de suivi** en clair, une seule fois. Lance l'analyse. |
| Analyser | `AnalyzeReportJob` (automatique) | `submitted` → `analyzing` → `in_validation`, avec une `Analysis` `proposed`, ou `failed` si l'extracteur échoue (l'analyste code alors à la main). |
| Corriger après envoi | `report.edit_submitted!(attrs, user:, tracking_code:)` | Jusqu'à la prise en charge et dans les 60 jours. Si le récit ou le débriefing change : retour à `submitted`, analyses supprimées, nouvelle analyse. Sinon, l'analyse reste. |
| Prendre en charge | `report.take_charge!(analyst)` | Ferme la modification par le déclarant, puis pré-remplit les champs restés vides avec la proposition du LLM (jamais un champ déjà rempli, jamais une valeur « non renseigné »). Si l'analyse arrive après la prise en charge, l'analyseur fait le même pré-remplissage. Idempotent. |
| Corriger les codes | `report.correct_coding!(analyst, attrs)` | Après la prise en charge, sous verrou : `event_type`, `discipline`, `environment`, `cause`, `severity`, `answers` (fusionnés comme une étape de formulaire ; une valeur vide efface). Écrit un `AccessLog` `code` si quelque chose change. |
| Rédiger le récit anonymisé | `report.write_anonymized_text!(analyst, text)` | Même conditions. Remplace le texte en entier ; vide l'efface. Le texte ne s'écrit que par cette méthode. |
| Poser une question | `report.ask_clarification!(analyst, body)` | Ouvre ou poursuit le fil. Ferme aussi la modification. Aucun mail sur le moment. |
| Répondre | `report.answer_clarification!(body, user:, tracking_code:)` | Seulement après une question de l'analyste. |
| Décider | `report.validate!(analyst)` (depuis `in_validation`), `report.reject!(analyst)` | Purge le brut (voir plus bas), écrit l'`AccessLog`. `validate!` exige le récit anonymisé (`RecordInvalid` sur `anonymized_text`), sauf si le brut a déjà été purgé à 180 jours. `reject!` efface le récit anonymisé : un rejet ne garde aucun texte. |

## Ce qui disparaît, et quand

Tout est automatique et identique pour tous : aucun écran ne doit permettre de changer une date de suppression.

| Quoi | Quand | Par |
| --- | --- | --- |
| Brouillon | 30 jours sans enregistrement | `PurgeExpiredDraftsJob`, chaque nuit |
| `ReportOwnership` (lien vers l'auteur) | Décision, ou 60 jours après la soumission | La décision, `CutOwnershipsJob` |
| `editable_until` (la fenêtre de modification) | Prise en charge, question, décision, ou fin des 60 jours | Ces méthodes, `CloseExpiredEditWindowsJob` |
| Récit, débriefing, réponses libres, fil, extraits du LLM, code de suivi | Décision, ou 180 jours après le 1er du mois de soumission sans décision (donc parfois 150 jours après l'envoi réel) | La décision, `PurgeOverdueRawContentJob` |
| Sessions expirées | Le lendemain de l'expiration | `PurgeExpiredSessionsJob` |
| Comptes déclarants inutilisés | Jamais connecté : fin du trimestre qui suit J+30 après la création. Sinon : fin du trimestre qui suit l'expiration de la dernière session + 12 mois. Jamais tant qu'une session existe, qu'un lien d'auteur vit, ou qu'un `AccessLog` ou un `AuditEvent` cite le compte. | `PurgeUnusedAccountsJob` |

Après la purge du brut, `raw_content_purged?` est vrai et il ne reste que les réponses codées. Après une validation, seuls restent les réponses codées et le récit anonymisé de l'analyste. Le LLM ne propose pas de texte (son schéma n'a que des champs codés) ; s'il en proposait un, il ne servirait qu'à pré-remplir le champ de l'analyste et ne survivrait pas à la décision : seules les valeurs des champs codés de la taxonomie sont conservées dans `Analysis`. Les modèles rattachés (`Narrative`, `Clarification`, `Casualty`, `Analysis`) sont en lecture seule une fois le rapport décidé. Après 180 jours sans décision, le statut ne bouge pas : l'analyste peut encore coder à la main et décider.

Les tâches tournent la nuit (3 h et 4 h, heure de Paris), le récapitulatif aux déclarants le lundi à 7 h (`config/recurring.yml`). En développement, rien ne tourne tout seul : lancer une tâche à la main (`bin/rails runner "CutOwnershipsJob.perform_now"`) pour voir son effet.

## Les deux modes

| | Confidentiel | Anonyme |
| --- | --- | --- |
| Compte | Connecté | Aucun : ne jamais passer de `user` |
| Retrouver le brouillon | `Report.owned_by(Current.user)` | `Report.find_draft_by_token(jeton du cookie)` |
| Retrouver le rapport soumis | `Report.owned_by(Current.user)`, tant que le lien vit | `Report.find_by_tracking_code(code)` |
| Prouver qu'on est le déclarant | `user: Current.user` | `tracking_code: code` |
| Être prévenu d'une question | Mail neutre hebdomadaire, sans contenu, tant que le lien vit et que le compte est actif | Revenir avec son code de suivi |
| Rapport introuvable pour le déclarant | À la décision ou 60 jours après la soumission | À la décision ou à la purge des 180 jours |

Les méthodes qui prennent `user:` et `tracking_code:` attendent l'un **ou** l'autre selon le mode, jamais les deux : passer les deux est un refus.

## Ce qui parle à l'extérieur

Derrière une interface, avec une doublure choisie dans `config/external_services.yml` :

- `Rails.configuration.x.llm_extractor` : `Llm::FakeExtractor` en développement et en test (JSON plausible et déterministe), `Llm::UnconfiguredExtractor` en production tant que Mistral n'est pas branché (chaque analyse échoue proprement, l'analyste code à la main).
- `Rails.configuration.x.membership_verifier` : `Membership::FakeVerifier`. Non utilisé par un écran pour l'instant.

Un écran n'appelle jamais l'extracteur : l'analyse est un job lancé par le modèle.
