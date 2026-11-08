# Pièges connus

## Formulaires et paramètres

- **Un hash non déclaré disparaît sans erreur.** `permit(narrative_attributes: [:raw_text, :free_text_answers])` jette les réponses libres en silence : il faut `free_text_answers: {}`. Même chose pour `answers: {}` sur le rapport et sur chaque victime.
- **Une étape remplace tout le hash.** `answers` et `free_text_answers` sont assignés en entier : une étape qui ne poste que ses champs efface les réponses des autres étapes. Voir [Écrans](ecrans.md#formulaire-en-étapes).
- **Les nombres arrivent en chaînes.** `answers` exige un `Integer` pour un champ `integer`, et refuse `""` pour un choix laissé vide. Le modèle ne convertit pas encore (voir [Écrans](ecrans.md#ce-que-le-modèle-ne-fournit-pas-encore)). `check_box` avec `multiple: true` ajoute aussi un champ caché vide si on ne lui passe pas `nil` en valeur décochée, comme le fait `choice_cards`.
- **Quatre champs vont en colonnes.** `discipline`, `environment`, `cause`, `severity` se postent au premier niveau du rapport, pas dans `answers`.
- **La taxonomie du rapport, pas la dernière.** Construire le formulaire avec `report.taxonomy_version`, pas `TaxonomyVersion.current` : une nouvelle version publiée pendant un brouillon ne doit pas changer ses questions.
- **Le récit peut manquer.** `report.narrative` vaut `nil` tant que rien n'a été saisi, et ses champs valent `nil` après la décision. Écrire `report.narrative&.raw_text`.

## Modèle

- **Pas de `created_at` ni d'`updated_at`** sur `Report`, `Narrative`, `Casualty`, `Analysis`, `Clarification`. C'est voulu (une date précise permettrait de retrouver l'auteur) : ne pas en ajouter, ne pas trier dessus.
- **Le statut ne s'écrit pas.** `report.update(status: "validated")` échoue en validation. Passer par la méthode du cycle de vie.
- **`report.validate!(analyst)` est la décision**, pas la validation d'ActiveModel. Pour lancer les validations : `report.valid?`.
- **`user:` ou `tracking_code:`, jamais les deux.** Et `user: nil` pour un rapport anonyme, même si la personne est connectée.
- **Ce qui est chiffré ne se cherche pas.** Récit, débriefs, réponses libres, fil, propositions : pas de `where`, pas de `LIKE`. Seuls l'e-mail et `user_ref` sont chiffrés de façon déterministe, pour être retrouvés par égalité.
- **Un rapport décidé est figé.** Ses victimes, son récit, son fil et ses analyses refusent toute écriture.
- **Les dates sont celles de Paris.** `Date.current`, jamais `Date.today` (fuseau du serveur).

## Contrôleurs

- **`require_role` suppose un compte.** Sur un contrôleur ouvert sans connexion, il plante (`Current.user` vaut `nil`) : ne pas le déclarer, et ajouter le contrôleur aux exemptions de `default_deny_spec.rb`.
- **Une portée partielle passe le test de refus par défaut.** `require_role :admin, only: :create` suffit à `default_deny_spec.rb` pour tout le contrôleur : les autres actions demandent un œil attentif en revue.
- **Un GET n'écrit jamais.** Pas de prise en charge à l'ouverture d'une fiche, pas de nettoyage de session au passage. Les scanners de messagerie suivent les liens des mails : un GET qui écrit serait déclenché par eux.

## Logs et débogage

- **Les identifiants sont masqués.** Tout UUID, toute adresse IPv4, tout e-mail, tout jeton de `/login/` apparaît en `[FILTERED]` dans les logs, et les paramètres sensibles aussi. C'est voulu ; pour déboguer, la console Rails. L'IPv6 n'est retirée que de la ligne de requête : ne jamais compter sur le masquage pour rattraper une ligne de log.
- **N'ajouter aucune ligne de log** qui nomme un rapport, un utilisateur ou un contenu, même en développement : le code part en production.

## Jobs et environnement

- **Rien ne tourne la nuit en développement.** Les tâches récurrentes ne sont planifiées qu'en production. Pour voir une coupure ou une purge, lancer le job à la main dans `bin/rails console` (`CutOwnershipsJob.perform_now`), éventuellement après `travel_to` dans un test.
- **L'analyse est asynchrone.** Après `submit!`, le rapport passe en `in_validation` quand le job a tourné (aussitôt en développement, avec l'extracteur factice). Une page qui suit l'analyse se recharge ; elle ne l'attend pas.
- **Les mails ne partent pas en développement** (`delivery_method = :test`), et aucun aperçu Action Mailer n'existe encore.
- **Base de développement.** Une migration cassée se corrige, jamais la base ; aucune tâche `db:*` destructive hors `RAILS_ENV=test` (voir `CLAUDE.md`). Si ta base locale ne suit plus après une migration corrigée sur place, voir avec Hugo. Une version de PostgreSQL différente de la CI réécrit les check constraints de `db/schema.rb` : ne pas committer ces changements-là.
- **L'horloge.** Rails refuse une migration datée de plus d'un jour dans le futur.
