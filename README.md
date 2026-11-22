# Site du laboratoire SNC

Site statique Jekyll, bilingue (français et anglais), du Laboratoire Sensorimotricité, Neuroplasticité et Communication (UQTR).
Adapté du gabarit [academic-website-template](https://github.com/sbryngelson/academic-website-template) (licence MIT) ;
la charte graphique reprend la maquette Canva du laboratoire.

## Modifier le contenu

| Contenu | Fichier |
| --- | --- |
| Actualités (seules celles de moins d'un an s'affichent ; les 3 premières vont sur l'accueil) | `_data/news.yml` |
| Présentation, parcours et distinctions d'Édith Durand | `_data/pi.yml` |
| Personnes étudiantes actuelles | `_data/team_members.yml` |
| Anciens membres (tableau triable, 10 par page) | `_data/alumni.yml` |
| Assistants et professionnels de recherche | `_data/assistants.yml` |
| Collaborateurs (page d'accueil) | `_data/collaborators.yml` |
| Projets en cours | `_data/projects.yml` |
| Subventions (page Projets, sans montants) | `_data/grants.yml` |
| Ressources et outils (cartes) | `_data/tools.yml` |
| Publications et présentations | `assets/ref.bib` |
| Menu et adresses des pages | `_data/nav.yml` |
| Libellés de l'interface en français et en anglais, adresse postale | `_data/i18n.yml` |
| Courriels, liens du département, CV | `_config.yml` |
| CV d'Édith Durand | `files/CV_Edith_Durand.pdf` |
| Textes des pages (les deux langues dans le même fichier) | `_includes/pages/*.html` |

Chaque page existe en deux versions : `_pages/*.html` (français) et `_pages/en/*.html` (anglais).
Les deux appellent le même gabarit de `_includes/pages/` ; le champ `ref` relie une page à sa traduction.

Dans `assets/ref.bib`, le champ `category` choisit la section de chaque entrée : `article`, `souspresse`,
`chapitre`, `invitee`, `orale`, `communication`, `affiche`, `vulgarisation`, `ressource` ou `protocole`.
Le champ `ym` (année × 100 + mois, par exemple `202609`) sert au filtre « moins d'un an » de la page Actualités.

## Filtre « moins d'un an »

La page Actualités ne garde que les éléments des douze mois précédant la **compilation** du site.
Le site doit donc être recompilé régulièrement pour que les anciennes actualités disparaissent.
Sur Netlify : *Site configuration > Build & deploy > Build hooks* crée une adresse qui relance la compilation ;
on peut l'appeler chaque semaine avec un service de tâches planifiées, ou simplement relancer un déploiement à la main.

## Compiler localement

Il faut Ruby 3.2 ou plus récent et, sous Windows, le DevKit de RubyInstaller.

```bash
bundle install
bundle exec jekyll serve
```

## Mise en ligne sur Netlify

Dans Netlify, choisir *Add new site > Import an existing project*, puis ce dépôt GitHub.
`netlify.toml` fournit déjà la commande de compilation et le dossier à publier ; chaque `git push` redéploie le site.

Les fichiers Excel sources contiennent des données confidentielles (salaires, évaluations d'enseignement, suivi éthique) :
ne jamais les placer dans ce dépôt.
