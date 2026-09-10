import pandas as pd
import itertools
import os
import statistics

#Creation des differentes operations et options
OPTIONS = {
    "missing_method": ["forward_fill", "interpolation"],
    "sample_size": ["full", "first_half", "second_half"],
    "threshold": ["05", "10", "15", "25"],
    "minimal_duration": [0, 10, 20], 
    "grouping_window": [0, 10, 20]
}

#Definition des differents seuils etudies
THRESHOLDS = {
    '05': {'lower': 0.995, 'upper': 1.005},
    '10': {'lower': 0.990, 'upper': 1.010},
    '15': {'lower': 0.985, 'upper': 1.015},
    '25': {'lower': 0.975, 'upper': 1.025}
}

#Definition variables globales
GRANULARITY = 5
START_DATE = pd.Timestamp("2022-01-01 00:00:00")
END_DATE = pd.Timestamp("2025-04-01 00:00:00")

#Fonction de chargement des donnees brutes
def dataLoading(stablecoin_file: str) -> pd.DataFrame:
    df_raw = pd.read_excel(stablecoin_file, parse_dates=['date'])
    df_raw = df_raw.rename(columns={'date': 'Date'}) 

    #Verification que les donnees sont comprises dans l'intervalle
    df_raw = df_raw[
        (df_raw["Date"] >= START_DATE) &
        (df_raw["Date"] <= END_DATE)
    ].copy()

    df_raw = df_raw.sort_values("Date").reset_index(drop=True)

    return df_raw

#Fonction de remplissage des obs manquantes (cree uniquement obs manquantes sans appliquer de methodologie)
def fill_missing_timestamps(df: pd.DataFrame, end_date: pd.Timestamp = None) -> pd.DataFrame:
    df = df.sort_values('Date').reset_index(drop=True)

    #Verification si doublons
    if df['Date'].duplicated().any():
        df = df.drop_duplicates(subset='Date', keep='first').reset_index(drop=True)

    #Verification pour chaque obs si un ecart de + 5 mins existe entre t et t+1
    new_rows = []
    for i in range(len(df) - 1):
        current_time = df.loc[i, 'Date']
        next_time = df.loc[i + 1, 'Date']
        time_diff = (next_time - current_time).total_seconds() / 60

        if time_diff > GRANULARITY:
            n_missing = int(time_diff // GRANULARITY) - 1
            for step in range(1, n_missing + 1):
                missing_time = current_time + pd.Timedelta(minutes=GRANULARITY * step)
                new_rows.append({'Date': missing_time, 'close': None})

    #Si obs manquante a la toute fin de l'echantillon
    if end_date is not None and len(df) > 0:
        last_time = df['Date'].iloc[-1] 
        time_diff_end = (end_date - last_time).total_seconds() / 60
        if time_diff_end > 0: # Si la serie est arretee avant la date de fin definie => Boucle pour remplir toutes les obs manquantes
            n_missing_end = int(time_diff_end // GRANULARITY)
            for step in range(1, n_missing_end + 1):
                missing_time = last_time + pd.Timedelta(minutes=GRANULARITY * step)
                new_rows.append({'Date': missing_time, 'close': None})

    if new_rows: #Si nouvelles lignes ont ete crees
        print(f"Ajout de {len(new_rows)} lignes pour combler les trous.")
        new_df = pd.DataFrame(new_rows)
        df = pd.concat([df, new_df], ignore_index=True)
    else:
        print("Aucun trou détecté dans les données.")

    df = df.sort_values('Date').reset_index(drop=True)
    
    print(f"Nombre total d'observations après correction : {len(df)}")
    return df

#Fonction permettant d'appliquer la methodologie de traitement des donnees manquantes
def apply_missing_methode(df: pd.DataFrame, missing_method: str) -> pd.DataFrame:
    df = df.copy()
    nb_missing_avant = df["close"].isna().sum()

    #Choix en fonction du parametre passe a la fonction
    if missing_method == "forward_fill":
        df["close"] = df["close"].ffill().bfill() #bfill securite si il manque premiere obs
    elif missing_method == "interpolation":
        df["close"] = df["close"].interpolate()
    else:
        raise ValueError(f"missing_method inconnu : {missing_method}")

    #Affichage infos
    nb_missing_apres = df["close"].isna().sum()
    nb_combles = nb_missing_avant - nb_missing_apres
    print(f"[{missing_method}] valeurs manquantes avant : {nb_missing_avant} | après : {nb_missing_apres} | comblées : {nb_combles}")

    return df

#Fonction permettant de decouper l'echantillon selon taille souhaitee
def apply_sample_size(df: pd.DataFrame, sample_size: str) -> pd.DataFrame:
    if sample_size == "full":
        return df.copy().reset_index(drop = True) #Reset_index est obligatoire au moins pour second_half car ID de la premiere obs sera 5000 et les fonctions suivantes utilisents des boucles commencants a 0
    elif sample_size == "first_half":
        return df.iloc[: len(df) // 2].copy().reset_index(drop = True)
    elif sample_size == "second_half":
        return df.iloc[len(df) // 2:].copy().reset_index(drop = True)
    else:
        raise ValueError(f"sample_size option inconnu: {sample_size}")

#Fonction permettant de calculer le nombre de depeg en fonction seuil souhaite
def apply_threshold(df: pd.DataFrame, threshold: str) -> pd.DataFrame:
    if threshold not in THRESHOLDS:
        raise ValueError(f"threshold option inconnu: {threshold}")

    #Recuperation des seuils dans la variable globale => Evite l'utilisation de if
    bounds = THRESHOLDS[threshold]
    df[f'Depeg_{threshold}'] = ((df['close'] <= bounds['lower']) | (df['close'] >= bounds['upper'])).astype(int)
    return df

#Fonction permettant de regrouper les depegs selon la fenetre de regroupement definie
def apply_grouping_window(df: pd.DataFrame, grouping_window: int, threshold: str):
    df['Depeg_serie'] = df[f'Depeg_{threshold}'].copy()
    df['Depeg_start'] = pd.Series(0, index=df.index, dtype=int)
 
    if grouping_window == 0:
        return
    if grouping_window not in (10, 20):
        raise ValueError(f"grouping window option inconnu: {grouping_window}")

    #Calcul du nombre d'obs a considerer pour regroupement
    window_size = max(1, grouping_window // GRANULARITY)
    n = len(df)
    idx = 0

    #Boucle tant qu'on arrive pas a la fin du df
    while idx < n:
        #Si debut de depeg on commence a regrouper
        if df['Depeg_serie'].iloc[idx] == 1:
            start_idx = idx
            end_idx = idx
            extend = True

            #Tant qu'on trouve des depegs on continue a chercher
            while extend:
                window_end = min(end_idx + window_size + 1, n)
                window = df['Depeg_serie'].iloc[end_idx + 1:window_end]
 
                if window.sum() >= 1:  # un seul depeg dans la fenetre suffit a regrouper
                    end_idx = window[window == 1].index[-1]
                else:
                    extend = False # Plus de depeg, fin du regroupement

            #On indique que toutes les obs font partie d'un depeg
            df.loc[start_idx:end_idx, 'Depeg_serie'] = 1
            #La recherche suivante commence a l'obs apres le depeg
            idx = end_idx + 1
        else:
            idx += 1

#Fonction permettant de verifier si depeg remplit la cond de duree minimum choisie
def apply_minimal_duration(df: pd.DataFrame, minimal_duration: int) -> dict:
   
    n = len(df)
 
    if minimal_duration == 0:
        min_consecutive = 1
    elif minimal_duration in (10, 20):
        min_consecutive = max(1, minimal_duration // GRANULARITY)
    else:
        raise ValueError(f"minimal duration option inconnu: {minimal_duration}")
 
    valid_series_count = 0
    positive_series_count = 0
    negative_series_count = 0
    series_durations = []
    positive_durations = []
    negative_durations = []

    #Tant qu'on arrive pas a la fin du df
    idx = 0
    while idx < n:
        if df['Depeg_serie'].iloc[idx] == 1: #On cherche les obs ou un depeg a ete detecte
            series_start = idx
            consecutive_count = 1
 
            while idx + 1 < n and df['Depeg_serie'].iloc[idx + 1] == 1: #Tant que des depegs sont detectes apres
                idx += 1
                consecutive_count += 1

            #Si nbr depegs consecutifs plus grand que le minimum demande
            if consecutive_count >= min_consecutive: #Depeg considere comme valide + calcul stats
                df.loc[series_start, 'Depeg_start'] = 1
                valid_series_count += 1
                duration_in_minute = consecutive_count * GRANULARITY
                series_durations.append(duration_in_minute)
 
                price = df['close'].iloc[series_start]
                if price < 1:
                    negative_series_count += 1
                    negative_durations.append(duration_in_minute)
                elif price > 1:
                    positive_series_count += 1
                    positive_durations.append(duration_in_minute)
            else:
                df.loc[series_start:series_start + consecutive_count - 1, 'Depeg_serie'] = 0 #Depeg inferieur a duree minimale, supression du depeg
 
            idx += 1
        else:
            idx += 1
 
    return {
        "valid_series_count": valid_series_count,
        "positive_series_count": positive_series_count,
        "negative_series_count": negative_series_count,
        "duration_min": min(series_durations) if series_durations else None,
        "duration_mean": statistics.mean(series_durations) if series_durations else None,
        "duration_median": statistics.median(series_durations) if series_durations else None,
        "duration_max": max(series_durations) if series_durations else None,
        "duration_total": sum(series_durations) if series_durations else 0,
        "positive_duration_mean": statistics.mean(positive_durations) if positive_durations else None,
        "negative_duration_mean": statistics.mean(negative_durations) if negative_durations else None,
    }

#Fonction qui permet de calculer un chemin individuellement     
def run_single_path(df_raw, missing_method, sample_size, threshold, minimal_duration,
                     grouping_window, path_id, output_dir):
    #Creation df temporaire et application des options passees en parametre
    df = df_raw.copy()
    df = apply_missing_methode(df, missing_method)
    df = apply_sample_size(df, sample_size)
    df = apply_threshold(df, threshold)
    apply_grouping_window(df, grouping_window, threshold)
    duration_stats = apply_minimal_duration(df, minimal_duration)
 
    # On n'exporte que ce dont R a besoin pour merger avec les jumps BTC et estimer l'effet
    export_df = df[['Date', 'close', 'Depeg_start', 'Depeg_serie']]
    export_path = os.path.join(output_dir, f"path_{path_id:03d}.csv")
    export_df.to_csv(export_path, index=False)
 
    result = {
        "path_id": path_id,
        "missing_method": missing_method,
        "sample_size": sample_size,
        "threshold": threshold,
        "minimal_duration": minimal_duration,
        "grouping_window": grouping_window,
        "csv_path": export_path,
    }
    result.update(duration_stats)
    return result

#Fonction permettant avec intertools d'executer les 216 chemins
def run_all_paths(stablecoin_name: str, stablecoin_file: str, base_output_dir: str = "paths_output"):
    #Creation des repertoires pour stocker resultats
    output_dir = os.path.join(base_output_dir, stablecoin_name)
    os.makedirs(output_dir, exist_ok=True)
 
    df_raw = dataLoading(stablecoin_file)  # lu une seule fois, copié à chaque chemin
    df_raw = fill_missing_timestamps(df_raw, END_DATE)

    #Verification tous les stablecoins meme taille d'echantillon
    print(f"{stablecoin_name} — première date : {df_raw['Date'].iloc[0]}")
    print(f"{stablecoin_name} — dernière date : {df_raw['Date'].iloc[-1]}")
    print(f"{stablecoin_name} — nombre de lignes : {len(df_raw)}")

    mid = len(df_raw) // 2
    print(f"{stablecoin_name} — fin first_half  : {df_raw['Date'].iloc[mid - 1]}")
    print(f"{stablecoin_name} — début second_half : {df_raw['Date'].iloc[mid]}")

    #Appel de la fonction permettant de calculer individuellement chaque chemin avec les options passees en parametre
    metadata = []
    path_id = 0
    for combo in itertools.product(*OPTIONS.values()):
        result = run_single_path(df_raw, *combo, path_id=path_id, output_dir=output_dir)
        metadata.append(result)
        path_id += 1

    #Enregistrement des resultats
    metadata_df = pd.DataFrame(metadata)
    metadata_df.to_csv(os.path.join(output_dir, "paths_metadata.csv"), index=False)
    print(f"{stablecoin_name} : {len(metadata_df)} chemins générés dans {output_dir}/")
    return metadata_df
 
#Fonction Main
if __name__ == "__main__":
    base_dir = "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Results" #Chemin du repertoire pour stocker resultats
    stablecoins = {
        "DAI": "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/DAI-USD-5m.xlsx", #Chemin pour retrouver les fichiers bruts des donnees
        "USDC": "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/USDC-USD-5m.xlsx",
        "USDT": "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/USDT-USD-5m.xlsx",
    }

    #Appel fonction de calcul de tous les chemins pour chaque stablecoin
    for name, file_path in stablecoins.items():
        run_all_paths(name, file_path, base_output_dir=base_dir)