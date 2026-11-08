# Contribuer à Spotter

Merci de votre intérêt. Spotter traite des récits d'accidents : la confidentialité passe avant tout le reste.

## Règles absolues

1. **Aucune donnée réelle dans le dépôt.** Ni récit, ni ligne d'un fichier de déclarations, ni nom, ni lieu précis, ni capture d'écran contenant de vraies données. Les tests, les seeds et les exemples de consignes du modèle de langage utilisent uniquement des données fictives.
2. **Aucun secret dans le dépôt.** Les clés (chiffrement, API, base de données) passent par les secrets de déploiement, jamais par le code.
3. **Aucune adresse IP conservée.** Toute modification qui journalise ou stocke une adresse IP, ou qui relie un RETEX à un utilisateur ailleurs que dans le lien chiffré prévu, sera refusée.

## Façon de travailler

- Une branche et une pull request par tâche. La fusion se fait après relecture par une autre personne.
- Les parties critiques (chiffrement, suppression du lien, logs, authentification) demandent une revue approfondie.
- Les tests doivent passer avant la fusion.
- Le code, les commentaires et les messages de commit sont en anglais.

## Signaler un bug ou proposer une idée

Ouvrez une issue en décrivant le problème avec des données fictives. Pour une faille de sécurité, suivez plutôt [SECURITY.md](SECURITY.md).
