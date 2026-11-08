# Vues

## CSP

La politique est stricte et appliquée (`config/initializers/content_security_policy.rb`) : tout vient de l'application, rien d'inline sans nonce.

- Aucun `<script>` dans une vue ni de `onclick=` : le JavaScript va dans un contrôleur Stimulus (`app/javascript/controllers/`), chargé par l'importmap.
- Aucun attribut `style=""` : le nonce ne couvre pas les attributs, le navigateur les ignore. Classes Tailwind seulement.
- Aucune ressource externe (CDN, police, image distante). Images : l'application ou `data:`.
- Une violation est refusée par le navigateur et rapportée dans le log (`/csp_reports`) : si un écran paraît cassé sans erreur Ruby, regarder la console du navigateur.

## Turbo

- Formulaire refusé : réponse 422, sinon Turbo n'affiche rien. Redirection après un envoi : 303 (`status: :see_other`).
- Turbo garde l'en-tête de la première page : aucun script inline dans un `<body>`, même avec un nonce.
- Confirmation avant une action irréversible : `data: { turbo_confirm: t(".confirm") }` sur le formulaire, ou le contrôleur Stimulus `confirm` pour un formulaire envoyé sans Turbo.
- Pas encore de Turbo Stream : la page 403 n'existe qu'en HTML, à étendre avant le premier.

## I18n

- Toute l'interface est en français dans `config/locales/fr.yml`, avec des clés en anglais. Dans une vue, la recherche paresseuse : `t(".title")` sous `fr.<contrôleur>.<action>.title`.
- Libellés des champs et messages d'erreur des modèles : `fr.activerecord.attributes` et `fr.activerecord.errors`.
- Les libellés de la taxonomie viennent de la base (`TaxonomyField#label`, `TaxonomyOption#label`, `definition`), pas des fichiers de traduction.
- Les noms de mois manquent : `l(report.submitted_on, format: "%B %Y")` affiche « Translation missing: fr.date.month_names » **sans lever d'erreur** (une spec ne le voit pas) tant que `fr.date.month_names` n'est pas dans `fr.yml`. Les ajouter là, sans gemme.
- Typographie : apostrophe courbe (’), espaces insécables avant `:`, `;`, `?`, `!` comme dans les clés existantes.

## Composants et jetons

`/dev/styleguide` montre tous les composants. Un composant est un partial de `app/views/components/` avec ses `locals:` déclarés en tête ; un nouveau composant s'ajoute au styleguide.

| Composant | Usage |
| --- | --- |
| `components/button` | Boutons et liens en forme de bouton |
| `components/text_field` | Champ texte ou `text_area` (`as: :text_area`), avec aide et erreur reliées par `aria-describedby` |
| `components/choice_cards` | Choix unique (radios) ou multiple (`multiple: true`, cases) en cartes |
| `components/steps` | Progression d'un formulaire en étapes |
| `components/flash` | Messages `notice` et `alert` (déjà dans le layout) |
| `components/empty_state` | Liste vide |

Jetons Tailwind (`app/assets/tailwind/application.css`) : couleurs `paper`, `surface`, `ink`, `muted`, `line`, `brand`, `success`, `danger`, `warning` (et leurs variantes `-soft`, `-strong`), rayons `rounded-control` et `rounded-card`, `min-h-touch` (3 rem) pour toute cible, `px-gutter` pour les marges latérales. Utiliser les jetons plutôt que des couleurs Tailwind brutes.

Sans `bin/dev`, `bin/rails tailwindcss:build` recompile la feuille (pour une capture, par exemple).

## Accessibilité

L'outil se remplit sur un téléphone, souvent le soir après une sortie, parfois dehors. D'où :

- Téléphone d'abord, puis ordinateur. Cibles d'au moins `min-h-touch`, contraste fort, pas d'effets.
- Chaque champ a son `label` ; chaque groupe de choix, son `fieldset` et sa `legend`.
- Une erreur est écrite en clair près du champ et reliée par `aria-describedby`, avec `aria-invalid`. `text_field` le fait ; `choice_cards` pas encore (ni `aria-describedby` ni état d'erreur) : à ajouter avant le formulaire.
- Le focus reste visible (contour orange global). Ne pas le retirer.
- Un seul `h1` par page, et `content_for :title` pour l'onglet.
- Le lien d'évitement vers `#main` est dans le layout : garder `id="main"`.

## Ce qu'une vue n'affiche jamais

- Quoi que ce soit qui relie un rapport à son auteur dans un écran de l'équipe (e-mail, compte, `ReportOwnership`).
- Une date plus précise que le mois pour un rapport.
- Un code de suivi, un jeton ou un code de secours ailleurs que dans la réponse qui le crée (avec `no-store` et `turbo-cache-control`, voir [Contrôleurs](controleurs.md#secrets-montrés-une-fois)).
- Le contenu d'un rapport dans un mail : les mails restent neutres, avec un lien vers `/login`.
