# Journal des décisions techniques

| Date | Décision | Raison | Alternatives écartées |
|---|---|---|---|
| 2026-10-29 | Moteur Godot 4.3+, GDScript à typage statique | Moteur libre, léger, adapté aux interfaces riches ; le typage limite les erreurs | Unity, C# généralisé |
| 2026-10-29 | Données de jeu en JSON dans `data/`, surchargeables par `user://mods/` | Moddable sans toucher au code | Données en dur, `.tres` uniquement |
| 2026-10-29 | Simulation séparée de l'affichage (`RefCounted` + commandes) | Sauvegardes simples, simulation déterministe, multijoueur possible plus tard | Logique dans les nœuds de scène |
| 2026-10-29 | Branches `main` / `develop` / branches de travail, versions SemVer `v0.N.0` par étape | Historique lisible, `main` toujours stable | Développement direct sur `main` |
