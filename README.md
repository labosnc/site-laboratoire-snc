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
| CV d'Édith Durand (masqué, voir plus bas) | `files/CV_Edith_Durand.pdf` |
| Textes des pages (les deux langues dans le même fichier) | `_includes/pages/*.html` |

Chaque page existe en deux versions : `_pages/*.html` (français) et `_pages/en/*.html` (anglais).
Les deux appellent le même gabarit de `_includes/pages/` ; le champ `ref` relie une page à sa traduction.

Dans `assets/ref.bib`, le champ `category` choisit la section de chaque entrée : `article`, `souspresse`,
`chapitre`, `invitee`, `orale`, `communication`, `affiche`, `vulgarisation`, `ressource` ou `protocole`.
Le champ `ym` (année × 100 + mois, par exemple `202609`) sert au filtre « moins d'un an » de la page Actualités.

## Mise à jour depuis le fichier Excel

Le script `scripts/mettre-a-jour.rb` relit le dossier d'évaluation (Excel), régénère les **subventions**
(`_data/grants.yml`, sans les montants) et les **publications et présentations** (`assets/ref.bib`, qui alimentent
aussi la page Actualités), affiche ce qui a changé, puis, après confirmation, fait le commit, l'envoie sur GitHub
et suit le déploiement jusqu'à la mise en ligne.

- **Windows :** double-cliquer sur `mettre-a-jour-windows.bat`, ou glisser le fichier Excel sur ce fichier.
- **macOS :** double-cliquer sur `mettre-a-jour-macos.command` (la première fois : clic droit > *Ouvrir*), puis glisser
  le fichier Excel dans la fenêtre du Terminal.
- **Ligne de commande :** `ruby scripts/mettre-a-jour.rb chemin/du/fichier.xlsx` ; `--oui` publie sans confirmation,
  `--sans-publier` régénère seulement les fichiers.

Le chemin du fichier Excel est mémorisé pour la fois suivante. Seules les feuilles « RECHER_Recap_subv… » et
« Références » sont lues, et seulement les colonnes publiques ; les colonnes sont repérées par leur en-tête.
Les entrées « en préparation » et « soumis » ne sont pas publiées. Les corrections de titres, d'organismes et de
références sont regroupées en tête du script (`GRANT_TITLES`, `FUNDERS`, `BIB_OVERRIDES`, `TYPOS`).
Les autres pages (équipe, anciens membres, projets, actualités en bref) se modifient toujours à la main dans `_data/`.

Prérequis, une seule fois par ordinateur :

1. **Git** et **Ruby** (2.6 ou plus récent, sans gem supplémentaire).
   Windows : [Git for Windows](https://git-scm.com/download/win) et [RubyInstaller](https://rubyinstaller.org/) (sans DevKit).
   macOS : `xcode-select --install` fournit Git ; Ruby est inclus dans macOS (ou `brew install ruby`).
2. Une copie du dépôt : `git clone https://github.com/labosnc/site-laboratoire-snc.git`
   (ou *Clone repository* dans GitHub Desktop).
3. Un accès en écriture au compte GitHub `labosnc` : sous Windows, Git ouvre le navigateur pour se connecter au
   premier envoi ; sous macOS, le plus simple est de se connecter une fois avec GitHub Desktop ou `gh auth login`.

Ne jamais placer le fichier Excel dans le dossier du site : le script refuse de le lire s'il s'y trouve.

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

## Mise en ligne sur GitHub Pages (solution actuelle)

Le fichier `.github/workflows/pages.yml` compile et publie le site à chaque `git push` sur `main`,
ainsi que chaque lundi (pour retirer les actualités de plus d'un an). On peut aussi le relancer à la main :
*Actions > Publier sur GitHub Pages > Run workflow*.
Réglage fait une seule fois : *Settings > Pages > Source : GitHub Actions*.

Adresse : https://labosnc.github.io/site-laboratoire-snc/, ou le domaine personnalisé une fois configuré dans
*Settings > Pages > Custom domain*. L'adresse et le sous-chemin sont fournis automatiquement par GitHub.

## Mise en ligne sur Netlify

Dans Netlify, choisir *Add new site > Import an existing project*, puis ce dépôt GitHub.
`netlify.toml` fournit déjà la commande de compilation et le dossier à publier ; chaque `git push` redéploie le site.

Les fichiers Excel sources contiennent des données confidentielles (salaires, évaluations d'enseignement, suivi éthique) :
ne jamais les placer dans ce dépôt.

## Éléments masqués pour le moment

- **CV d'Édith Durand :** le PDF a été retiré du dépôt (une copie est conservée hors du dépôt, dans `../CV_Edith_Durand.pdf`).
  Pour le republier : le replacer dans `files/`, l'enlever de `.gitignore`, puis dans `_config.yml`,
  décommenter `cv_file` et retirer le PDF de la liste `exclude`.
- **Page Ressources et outils :** retirer `published: false` de `_pages/ressources.html` et `_pages/en/resources.html`,
  et `hidden: true` de l'entrée `tools` dans `_data/nav.yml`.
