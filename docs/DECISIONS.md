# Journal des décisions techniques

| Date | Décision | Raison | Alternatives écartées |
|---|---|---|---|
| 2026-10-29 | Moteur Godot 4.3+, GDScript à typage statique | Moteur libre, léger, adapté aux interfaces riches ; le typage limite les erreurs | Unity, C# généralisé |
| 2026-10-29 | Données de jeu en JSON dans `data/`, surchargeables par `user://mods/` | Moddable sans toucher au code | Données en dur, `.tres` uniquement |
| 2026-10-29 | Simulation séparée de l'affichage (`RefCounted` + commandes) | Sauvegardes simples, simulation déterministe, multijoueur possible plus tard | Logique dans les nœuds de scène |
| 2026-10-29 | Branches `main` / `develop` / branches de travail, versions SemVer `v0.N.0` par étape | Historique lisible, `main` toujours stable | Développement direct sur `main` |
| 2026-10-29 | Version minimale Godot 4.7 (au lieu de 4.3) | Le projet est développé et testé avec 4.7.2 ; GUT 9.7 cible 4.7 | Rester compatible 4.3 sans pouvoir le tester |
| 2026-10-29 | Données regroupées par catégorie = dossier (`data/countries/*.json` → `countries`), fichiers fusionnés par identifiant | Un mod ou un DLC ajoute un fichier sans toucher aux existants | Un fichier unique par type, surcharge fichier par fichier |
| 2026-10-29 | Fusion des mods : objets fusionnés, tableaux remplacés, `null` supprime, `__replace` remplace un objet | Règles simples et prévisibles | Concaténation des tableaux (impossible de retirer un élément) |
| 2026-10-29 | Schémas maison (sous-ensemble de JSON Schema) avec `ref` pour les références entre catégories | Lisible par les moddeurs, détecte les identifiants inexistants | JSON Schema complet (lourd), pas de validation |
| 2026-10-29 | Traductions en CSV lues au démarrage (import Godot « keep ») plutôt qu'importées par l'éditeur | Les mods peuvent ajouter ou remplacer des textes | Import CSV natif de Godot (figé à l'export) |
| 2026-10-29 | Idéologies, régimes, terrains et ressources sont des catégories de données, référencées par identifiant | Extensibles par les mods, sans liste figée dans le code | Énumérations dans le code |
| 2026-10-29 | Autoload supplémentaire `SystemRegistry` (fournisseurs par clé, priorité) | Point d'extension pour remplacer des modules (militaire, IA…) par un DLC | Registre dans `GameState` (réinitialisé à chaque partie) |
| 2026-10-29 | État de partie dans une classe pure `SimState`, modifiée uniquement par des `Command` en file | Séparation simulation / affichage, déterminisme, sauvegardes | L'UI modifie l'état directement |
| 2026-10-29 | Mods utilisateur désactivés pour l'instant (`ModManager.USER_MODS_ENABLED = false`), mécanisme de fusion conservé | Pas de compatibilité mod à garantir pendant le développement ; la fusion sert aussi aux DLC | Supprimer tout le code mod |
| 2026-10-29 | Déclarations non typées traitées comme des erreurs (`untyped_declaration = 2`) | Rend le typage statique obligatoire | Simple avertissement |
