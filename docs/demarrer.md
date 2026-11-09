# Démarrer

## Installer

Prérequis :

- Ruby, version de `.ruby-version` (par exemple avec `rbenv`, `asdf` ou `mise`) ;
- PostgreSQL 17, installé sur le poste, ou Docker : `bin/setup` lance alors la base de `compose.yaml` tout seul ;
- Chrome, pour les tests système (passkeys) ;
- `gitleaks`, conseillé : le hook avant push l'utilise s'il est installé, la CI le lance de toute façon.

Aucune clé n'est à demander : les clés de chiffrement de développement et de test sont en clair dans `config/environments/`, sans valeur ailleurs. La clé maître (`config/master.key`) ne sert qu'à la production.

```sh
git clone git@github.com:SNAPEC/spotter.git
cd spotter
scripts/ci/install-hooks.sh   # une fois : hooks git (gitleaks, RuboCop, Brakeman, bundler-audit)
bin/setup                     # gems, base, taxonomie v0 et données fictives, puis lance bin/dev
```

## Lancer

```sh
bin/dev    # serveur Rails et Tailwind en mode watch, sur http://localhost:3000
```

- `/dev/login` : connexion en un clic à un compte fictif (`declarant@example.test`, `analyste@example.test`, `admin@example.test`, `admin2@example.test`), sans mail ni passkey.
- `/dev/styleguide` : tous les composants.
- `bin/rails console` : pour regarder les données (déchiffrées) et lancer une méthode du modèle à la main.

Les deux pages `/dev/*` répondent 404 hors développement.

`bin/setup` ne recharge pas les données fictives d'une base qui existe déjà ; les seeds ne tournent qu'à la création.

## Travailler

Une tâche = une branche = une pull request.

1. Partir de `main` à jour : `git switch main && git pull && git switch -c nom-de-la-tache`.
2. Petits commits, un sujet chacun, message en anglais à l'impératif (« Add the report summary screen »). Ajouter les fichiers par leur chemin (`git add app/views/declarant/…`), jamais `git add -A`, pour ne rien committer par mégarde.
3. Avant de pousser :

   ```sh
   bundle exec rspec
   bin/rubocop
   bin/brakeman --no-pager -q
   ```

   Le hook relance l'essentiel au push ; la CI relance tout.
4. Pousser la branche et ouvrir la PR **en brouillon** : `git push -u origin nom-de-la-tache`, puis `gh pr create --draft`.
5. Hugo relit. Une fois les retours traités, la PR passe « prête » (`gh pr ready`) et elle est fusionnée. On ne pousse jamais sur `main`, et on ne fusionne pas une PR encore en brouillon.

Les zones critiques (chiffrement, suppression du lien d'auteur, logs, authentification) demandent une relecture approfondie : le signaler dans la description de la PR.

Une question de produit (un texte, un champ obligatoire, un comportement) se pose avant de coder, pas dans la PR : les décisions sont tenues dans le dépôt privé de pilotage.

## Avec Claude Code

`CLAUDE.md` à la racine donne les règles du projet à Claude Code ; il se charge tout seul quand la session s'ouvre dans le dossier du dépôt. Deux agents sont définis dans `.claude/agents/` : `spotter-rails` implémente une tâche validée, `spotter-review` relit une branche sans rien modifier. Le second est utile avant de demander une relecture humaine.

## Ensuite

Lire [Domaine](domaine.md), puis [Contrôleurs](controleurs.md) et [Écrans](ecrans.md) : c'est là que se trouve ce qu'un écran doit appeler.
