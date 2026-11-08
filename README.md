# Spotter

**Trouver la parade, ensemble.** *Spot the risk, together.*

Spotter est l'outil de retour d'expérience (RETEX) du SNAPEC, le Syndicat national des professionnels de l'escalade et du canyon. Il permet aux moniteurs et monitrices de raconter un accident, un incident ou une situation dangereuse, pour que les autres en tirent des enseignements.

> **Statut : en conception.** Le premier prototype couvre l'escalade (salle, bloc, falaise, grande voie, terrain d'aventure). Le canyon viendra ensuite.

## Principes

- **Confidentialité.** Un RETEX naît confidentiel et finit anonyme. Le lien entre un RETEX et son auteur est chiffré, puis supprimé automatiquement à la validation, au plus tard après un délai fixe annoncé à l'avance. Un mode anonyme sans compte est aussi proposé.
- **Minimisation.** Aucune adresse IP conservée, ni en base ni dans les logs. Dates arrondies au mois, lieux généralisés.
- **Humain dans la boucle.** Un modèle de langage open source propose une anonymisation et une codification. Une personne de la commission accidentologie valide toujours avant que quoi que ce soit soit utilisé.
- **Mobile first.** Pensé pour être rempli sur téléphone, à froid, le soir.
- **Transparence.** Le code est public, sous licence AGPL-3.0.

## Stack prévue

- Ruby on Rails 8, Hotwire (Turbo et Stimulus), Tailwind CSS
- PostgreSQL, Solid Queue, Active Record Encryption
- Modèle Mistral via Scaleway Generative APIs
- Déploiement avec Kamal sur une machine virtuelle Scaleway, en France

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Règle absolue : **aucune donnée réelle** dans ce dépôt, ni dans le code, ni dans les tests, ni dans les captures d'écran.

## Signaler une faille de sécurité

Voir [SECURITY.md](SECURITY.md). Merci de ne pas ouvrir d'issue publique pour une faille.

## Licence

[GNU Affero General Public License v3.0](LICENSE). Si vous modifiez Spotter et le proposez en ligne, vous devez publier vos modifications sous la même licence.
