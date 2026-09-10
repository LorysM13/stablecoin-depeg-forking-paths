# Estimation et agrégation de l'effet de contagion sur les 216 chemins

Ce script R constitue la seconde étape du projet. À partir des fichiers générés par le script Python, il estime l'effet de contagion entre les épisodes de dépeg de chaque stablecoin et les sauts significatifs du Bitcoin sur chacun des 216 chemins, étudie la distribution de ces effets puis les agrège afin d'évaluer la robustesse du résultat obtenu dans notre précédent mémoire (Massaux, 2025).

## Détection des sauts du Bitcoin

Les sauts significatifs du prix de clôture du Bitcoin sont détectés à partir de la statistique de Boudt et al. (2011), selon la méthodologie employée dans notre précédent mémoire et inspirée de Perez Riaza et Gnabo (2024). Cette statistique rapporte le rendement intra-journalier à une estimation de la volatilité qui tient compte de sa composante périodique.

## Estimation de l'effet sur chaque chemin

Pour chaque chemin, les épisodes de dépeg identifiés par le script Python sont fusionnés avec les sauts du Bitcoin. La fenêtre évènementielle regroupe l'ensemble des observations comprises entre le début de chaque épisode de dépeg et les quatre heures suivantes. L'échantillon de contrôle regroupe les observations qui n'appartiennent ni à la fenêtre évènementielle, ni à un épisode de dépeg en cours.

Nous estimons ensuite la régression logistique binaire suivante.

```
log( P(jump = 1) / P(jump = 0) ) = β0 + β1 · isDepegPeriod
```

Le coefficient β1 constitue l'effet du chemin, dont nous extrayons également l'écart-type et le critère d'information d'Akaike (AIC). Le coefficient s'exprimant en log-odds, nous calculons en complément l'effet marginal, qui correspond à la variation de la probabilité d'observer un saut lorsque `isDepegPeriod` passe de 0 à 1. Le modèle ne comportant qu'une seule variable explicative binaire, cet effet marginal se réduit à la différence entre la proportion de sauts observée dans la fenêtre évènementielle et celle observée dans l'échantillon de contrôle. Ses erreurs-types sont calculées par la méthode delta (Norton et al., 2019).

Les chemins pour lesquels aucun épisode de dépeg n'est détecté ne permettent pas de construire de fenêtre évènementielle et sont donc exclus de l'estimation.

## Agrégation des résultats

Les effets des différents chemins sont agrégés sous la forme d'une moyenne pondérée par les poids d'Akaike (Coqueret, 2023). L'AIC n'étant comparable que pour des modèles estimés sur un même jeu de données (Burnham & Anderson, 2004), ces poids, et donc l'effet agrégé, sont calculés séparément pour chacun des trois découpages d'échantillon (complet, première moitié et seconde moitié).

Nous calculons ensuite la variance de l'effet agrégé en supposant une corrélation parfaite entre les estimateurs des différents chemins, puis l'intervalle de confiance associé, dont la précision croît avec le nombre de chemins (Coqueret, 2023).

## Position du résultat original

Le résultat du chemin de référence (chemin 005), correspondant aux choix de notre précédent mémoire, est situé au sein de la distribution des effets grâce à l'indicateur Ease to Confirm (EtC), complément de l'indicateur Odds of Favorable Outcome (OFO), avec un seuil fixé au quantile à 90 % de la distribution (Coqueret, 2023). Un EtC proche de 1 indique un résultat facilement reproductible à travers les chemins, tandis qu'un EtC proche de 0 signale un résultat atypique.

Enfin, une specification curve permet de visualiser l'effet de chaque chemin ainsi que les options qui le composent.

## Packages utilisés

`data.table`, `dplyr`, `ggplot2`, `kableExtra`, `highfrequency`

## Utilisation

Les chemins vers les fichiers générés par le script Python (`<STABLECOIN>/path_XXX.csv`) et vers les données du Bitcoin sont à adapter en début de script.

## Références

- Boudt, K., Croux, C., & Laurent, S. (2011). Robust estimation of intraweek periodicity in volatility and jump detection. *Journal of Empirical Finance*, 18(2), 353-367.
- Burnham, K. P., & Anderson, D. R. (2004). Multimodel inference: Understanding AIC and BIC in model selection. *Sociological Methods & Research*, 33(2), 261-304.
- Coqueret, G. (2023). *Forking paths in financial economics* (arXiv:2401.08606). https://doi.org/10.48550/arXiv.2401.08606
- Massaux, L. (2025). *Cartographie comparative des stablecoins* [Mémoire de master, Université de Namur].
- Norton, E. C., Dowd, B. E., & Maciejewski, M. L. (2019). Marginal Effects—Quantifying the Effect of Changes in Risk Factors in Logistic Regression Models. *JAMA*, 321(13), 1304-1305.
- Perez Riaza, B., & Gnabo, J.-Y. (2024). *Spillover Effects of Tether Depegs on Bitcoin Jumps and Crypto-Asset Market Cojumps* (SSRN No 4996933).