# Déployer

La production tourne sur une seule machine virtuelle Scaleway, déployée avec Kamal (`config/deploy.yml`). Les images passent par le registre local de Kamal, poussé à travers un tunnel SSH : il n'y a pas de registre à configurer.

## Automatiquement, depuis la CI

Chaque push sur `main` (donc chaque pull request fusionnée) lance le job `deploy` du workflow `CI`, une fois les autres jobs du même workflow au vert. Le job attend ensuite l'approbation d'un relecteur de l'environnement GitHub `production` : Actions, le run, « Review deployments ». Sans approbation, rien ne part.

- Deux déploiements ne se chevauchent jamais : un push arrivé pendant un déploiement attend la fin du premier.
- Une pull request, même d'un fork, ne déploie jamais : le job ne tourne que sur `main`, et l'environnement `production` n'accepte que cette branche.
- Les secrets sont ceux de l'environnement `production` : `RAILS_MASTER_KEY`, `SPOTTER_DATABASE_PASSWORD`, `SPOTTER_SERVER_IP`, `DEPLOY_SSH_KEY` (clé privée dédiée au déploiement) et `DEPLOY_KNOWN_HOSTS` (la ligne de clé d'hôte du serveur, la seule acceptée).
- Les logs d'Actions sont publics. Ne jamais ajouter `--verbose` à `kamal` dans le workflow : à ce niveau, Kamal affiche l'environnement de chaque commande, secrets compris. L'adresse du serveur est masquée.

## À la main

Depuis un poste qui a `config/master.key` et une clé SSH autorisée sur le serveur, sur `main` à jour et propre :

```sh
export SPOTTER_SERVER_IP=…            # l'adresse du serveur, depuis le gestionnaire de mots de passe
export SPOTTER_DATABASE_PASSWORD=…    # idem
bin/kamal deploy
```

Le hook `pre-connect` refuse de continuer si `SPOTTER_DATABASE_PASSWORD` n'est pas exporté. Le verrou de Kamal empêche un déploiement manuel de croiser celui de la CI.
