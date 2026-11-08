# Documentation pour construire les écrans

Le socle livre les modèles du domaine, l'authentification et des écrans vides par rôle. Ces pages disent ce qu'il faut savoir pour construire les écrans par-dessus sans toucher au back, et sans casser les garanties de confidentialité qui sont la raison d'être de Spotter.

Ordre de lecture conseillé :

1. [Domaine](domaine.md) : les modèles, le cycle de vie d'un RETEX, ce qui est supprimé et quand.
2. [Contrôleurs](controleurs.md) : la forme d'un contrôleur, l'autorisation, les erreurs et leurs codes HTTP.
3. [Écrans](ecrans.md) : une fiche par écran à construire, avec la méthode du modèle à appeler.
4. [Vues](vues.md) : CSP, Turbo, I18n, composants, accessibilité.
5. [Pièges](pieges.md) : ce qui a déjà mordu ou mordra.
6. [Tests](tests.md) : comment tester un écran.

Les règles générales (pas de donnée réelle, pas d'IP, un rapport ne pointe jamais vers son auteur…) sont dans [`CLAUDE.md`](../CLAUDE.md) et s'appliquent partout. Le contenu métier des écrans (questions du formulaire, découpage en étapes, textes) vient des documents de conception, privés : ils ne sont pas recopiés ici.

En développement : `bin/setup` crée une base avec quatre comptes et quatorze RETEX fictifs à toutes les étapes ; `/dev/login` connecte en un clic, `/dev/styleguide` montre les composants.
