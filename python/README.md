# Détection des épisodes de dépeg par la méthodologie des forking paths

Ce script Python constitue la première étape du projet. Il identifie les épisodes de dépeg de trois stablecoins (USDT, USDC et DAI) selon 216 chemins méthodologiques distincts et exporte, pour chacun d'eux, les données nécessaires à l'estimation de l'effet de contagion réalisée dans le script R.

## La méthodologie des forking paths

Nous nous basons sur la méthodologie des forking paths proposée par Coqueret (2023). Celle-ci consiste à lister un ensemble d'alternatives méthodologiques raisonnables afin de mesurer dans quelle mesure la méthodologie retenue par le chercheur influence les résultats obtenus, autrement dit si ces résultats sont sensibles aux choix méthodologiques. Contrairement au bootstrap, qui fait varier les données, cette approche conserve les mêmes données et fait varier les choix du chercheur.

Concrètement, à chaque étape de la méthodologie, nous étudions les différents choix raisonnables possibles, appelés opérations, et nous déterminons pour chacune d'elles plusieurs options. La combinaison de l'ensemble de ces options génère des chemins, chacun conduisant à sa propre identification des épisodes de dépeg.

## Opérations et options retenues

Il n'existe pas de définition consensuelle d'un épisode de dépeg dans la littérature. Pour les trois opérations liées à cette définition, nous avons donc retenu les options raisonnables que nous y avons identifiées. Les deux dernières opérations concernent l'échantillon de données.

| Opération | Options | Paramètre |
|---|---|---|
| Seuil de référence | 0,5 %, 1 %, 1,5 % et 2,5 % | `threshold` |
| Durée minimale de l'épisode | 1 observation (5 min), 2 observations (10 min) ou 4 observations (20 min) | `minimal_duration` |
| Fenêtre de regroupement | aucune, 10 min ou 20 min | `grouping_window` |
| Traitement des données manquantes | forward fill ou interpolation | `missing_method` |
| Découpage en sous-échantillons | complet, première moitié ou seconde moitié | `sample_size` |

La combinaison de ces options génère 4 × 3 × 3 × 2 × 3 = 216 chemins par stablecoin.

**Seuil de référence.** Une observation est considérée comme hors ancrage lorsque son prix de clôture s'écarte de 1 $ d'au moins le seuil retenu, à la hausse comme à la baisse.

**Durée minimale de l'épisode.** Elle permet d'éviter de comptabiliser en tant que dépeg ce qui ne relève que du bruit. Une seule observation hors seuil suffit dans l'option la moins restrictive, tandis que les deux autres options exigent respectivement 2 et 4 observations consécutives.

**Fenêtre de regroupement.** Lorsqu'un dépeg se produit peu après un autre, les deux sont fusionnés en un seul épisode si le second débute au plus 10 ou 20 minutes après la fin du premier, selon l'option retenue.

**Traitement des données manquantes.** Les horodatages manquants sont d'abord recréés, puis comblés soit par forward fill (dernière valeur disponible), soit par interpolation linéaire. Ces deux méthodes conservent un nombre identique d'observations pour les trois stablecoins et garantissent ainsi leur comparabilité.

**Découpage en sous-échantillons.** Nous retenons trois sous-échantillons. L'échantillon complet couvre la période du 1er janvier 2022 au 1er avril 2025. La première moitié, jusqu'au 17 août 2023 à 11h55, regroupe les principaux évènements de crise, notamment l'effondrement de Terra-Luna (mai 2022), la faillite de FTX (novembre 2022) et l'effondrement de la Silicon Valley Bank (mars 2023). La seconde moitié correspond quant à elle à une période plus calme.

Le chemin 005 (forward fill, échantillon complet, seuil de 0,5 %, durée minimale de 10 minutes et fenêtre de regroupement de 20 minutes) correspond aux choix retenus dans notre précédent mémoire (Massaux, 2025) et sert de chemin de référence.

## Structure du code

Chaque opération est représentée par une fonction, l'option retenue lui étant transmise en paramètre. Une fonction permet ensuite, grâce à `itertools.product`, de générer la combinaison de tous les chemins possibles et appelle, pour chacun d'eux, une fonction qui calcule le chemin individuellement en appelant successivement les fonctions des différentes opérations.

| Fonction | Rôle |
|---|---|
| `dataLoading` | Chargement des données brutes et restriction à la période étudiée |
| `fill_missing_timestamps` | Recréation des horodatages manquants, sans leur attribuer de valeur |
| `apply_missing_methode` | Traitement des données manquantes (forward fill ou interpolation) |
| `apply_sample_size` | Découpage en sous-échantillons |
| `apply_threshold` | Identification des observations hors seuil |
| `apply_grouping_window` | Fusion des dépegs rapprochés selon la fenêtre de regroupement |
| `apply_minimal_duration` | Validation des épisodes selon la durée minimale et calcul des statistiques de durée |
| `run_single_path` | Calcul d'un chemin individuel à partir des options qui lui sont passées |
| `run_all_paths` | Génération des 216 combinaisons avec `itertools.product` et appel de `run_single_path` pour chacune |

Au sein d'un chemin, les opérations sont appliquées dans l'ordre suivant.

```
données manquantes → découpage → seuil → fenêtre de regroupement → durée minimale
```

La fenêtre de regroupement étant appliquée avant la durée minimale, deux dépegs rapprochés et fusionnés peuvent ensemble satisfaire la durée minimale exigée.

## Données d'entrée

Le script attend un fichier Excel par stablecoin, avec une granularité de 5 minutes et au minimum les colonnes `date` et `close`. Les données de l'USDT et du DAI proviennent de l'API de Coinbase, celles de l'USDC de l'API de Kraken. Elles ne sont pas incluses dans ce dépôt.

## Sorties

Pour chaque stablecoin, le script crée un dossier `<STABLECOIN>/` contenant les fichiers suivants.

`path_000.csv` à `path_215.csv`, un fichier par chemin, avec les colonnes

| Colonne | Contenu |
|---|---|
| `Date` | Horodatage de l'observation |
| `close` | Prix de clôture après traitement des données manquantes |
| `Depeg_start` | 1 pour la première observation de chaque épisode de dépeg valide, 0 sinon |
| `Depeg_serie` | 1 pour toutes les observations appartenant à un épisode de dépeg valide, 0 sinon |

`Depeg_start` sert, dans le script R, à construire la fenêtre évènementielle de quatre heures suivant le début de chaque épisode, tandis que `Depeg_serie` permet d'exclure de l'échantillon de contrôle les observations appartenant à un dépeg en cours.

`paths_metadata.csv` reprend, pour chaque chemin, les options retenues ainsi que les statistiques descriptives des épisodes détectés (nombre d'épisodes, nombre d'épisodes positifs et négatifs, durées minimale, moyenne, médiane, maximale et totale, durée moyenne des épisodes positifs et négatifs). Un épisode est qualifié de positif ou de négatif selon que le prix au début de l'épisode est supérieur ou inférieur à 1 $.

## Utilisation

```bash
pip install pandas openpyxl
python depeg_algo_forking_paths.py
```

Les chemins vers les fichiers de données et le répertoire de sortie sont à adapter dans le bloc `if __name__ == "__main__":` en fin de script.

## Références

- Coqueret, G. (2023). *Forking paths in financial economics* (arXiv:2401.08606). https://doi.org/10.48550/arXiv.2401.08606
- Massaux, L. (2025). *Cartographie comparative des stablecoins* [Mémoire de master, Université de Namur].
- Perez Riaza, B., & Gnabo, J.-Y. (2024). *Spillover Effects of Tether Depegs on Bitcoin Jumps and Crypto-Asset Market Cojumps* (SSRN No 4996933).
