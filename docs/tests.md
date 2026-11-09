# Tests

RSpec. Les modèles sont déjà testés : un écran se teste surtout par une spec de requête, et par une spec système quand il dépend de JavaScript.

```sh
bundle exec rspec                 # toute la suite
bundle exec rspec spec/requests   # un dossier
bin/rubocop                       # style
bin/brakeman --no-pager -q        # sécurité
```

Le hook installé par `scripts/ci/install-hooks.sh` tourne avant chaque push, selon les fichiers touchés : gitleaks, RuboCop, Brakeman (si `app/`, `config/` ou `lib/` changent), bundler-audit (si `Gemfile.lock` change). La CI relance tout.

## Données

- Fictives seulement : adresses en `example.com` ou `example.test`, récits inventés. Jamais un vrai récit, un vrai lieu, une vraie date d'accident.
- Pas de fixtures ni de factories : chaque spec crée ce dont elle a besoin. La taxonomie s'importe en tête :

```ruby
let!(:taxonomy) { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }
```

- Un rapport s'amène à l'état voulu par les méthodes du modèle (`Report.start_draft!`, `save_draft!`, `submit!`, `take_charge!`…), jamais en écrivant le statut.

## Se connecter dans une spec de requête

```ruby
def sign_in(user)
  post magic_link_path(user.magic_link_token)
  Session.find_by!(user: user).update!(passkey_verified: true) if user.staff?
end
```

Voir `spec/requests/authorization_spec.rb`.

## Ce qu'une spec d'écran vérifie

- Le cas qui marche : code HTTP, redirection, effet sur le rapport (`report.reload.status`, `report.clarifications.count`…).
- Le formulaire refusé : 422 et le message d'erreur dans la page.
- L'accès : 302 vers `/login` sans connexion, 403 pour un mauvais rôle, **404 pour le rapport d'un autre déclarant** ou un code de suivi faux.
- Le changement d'état concurrent : un rapport pris en charge entre l'affichage et l'envoi donne la redirection prévue, pas une erreur 500.
- La limite de débit, quand l'action en porte une.
- Les secrets montrés une fois : présents dans la réponse, `Cache-Control: no-store`, absents de la page suivante.

## Temps et jobs

- Les échéances se testent avec `travel_to(Date.new(2026, 11, 17)) { … }` (dates fictives).
- Un job se teste par ses effets : `perform_enqueued_jobs { … }` (avec `include ActiveJob::TestHelper` dans la spec, comme `no_ip_anywhere_spec.rb`), puis l'état de la base. Pas de test qui vérifie seulement qu'un job a été mis en file.

## Interdits

- `allow_any_instance_of`, `send` vers une méthode privée, `instance_variable_get`.
- Une spec qui dépend de l'heure réelle.
- Un appel réseau : l'extracteur et le vérificateur d'adhésion sont des doublures en test.

## Garde-fous déjà en place

Ces specs protègent des règles de tout le dépôt ; un nouvel écran peut les faire échouer, c'est leur rôle :

- `spec/requests/default_deny_spec.rb` : chaque contrôleur déclare ses rôles ou figure dans les exemptions.
- `spec/requests/no_ip_anywhere_spec.rb` : aucune IP en base ni dans les logs.
- `spec/requests/logging_spec.rb`, `spec/initializers/filter_parameter_logging_spec.rb` : rien de sensible dans les logs.
- `spec/requests/content_security_policy_spec.rb` et `spec/system/passkey_spec.rb` : la CSP tient, sans violation dans le navigateur. Une spec système d'écran peut reprendre le relevé des violations de `passkey_spec.rb`.
