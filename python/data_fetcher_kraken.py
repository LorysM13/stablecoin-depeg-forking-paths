import requests
import pandas as pd
from datetime import datetime, timezone
import time
import os
import json


def resolve_kraken_pair(pair_altname):
    """
    Vérifie/résout le nom interne exact de la paire chez Kraken via l'endpoint
    public AssetPairs, pour être sûr d'utiliser la bonne clé dans les réponses.
    """
    url = 'https://api.kraken.com/0/public/AssetPairs'
    response = requests.get(url, params={'pair': pair_altname})
    data = response.json()

    if data.get('error'):
        raise ValueError(f"Erreur AssetPairs pour {pair_altname} : {data['error']}")

    result_keys = list(data['result'].keys())
    if len(result_keys) != 1:
        raise ValueError(f"Résolution ambiguë pour {pair_altname} : {result_keys}")

    resolved_key = result_keys[0]
    print(f"Paire '{pair_altname}' résolue en clé interne Kraken : '{resolved_key}'")
    return resolved_key


def download_and_reconstruct_kraken_ohlc(pair='USDCUSD', start_date='2022-01-01', end_date='2025-04-02',
                                          output_dir='output', interval_min=5, checkpoint_every=200):
    """
    Télécharge l'historique complet des transactions (tick-par-tick) via l'endpoint
    public Trades de Kraken (seul endpoint donnant l'historique complet, contrairement
    à /OHLC qui est limité aux 720 dernières bougies quel que soit 'since'), puis
    reconstruit des bougies OHLC de {interval_min} minutes par ré-échantillonnage.

    pair             : altname Kraken, ex 'USDCUSD'
    start_date       : 'YYYY-MM-DD'
    end_date         : 'YYYY-MM-DD'
    interval_min     : granularite des bougies reconstruites, en minutes
    output_dir       : dossier de sortie
    checkpoint_every : nombre d'appels API entre deux sauvegardes intermediaires.
    """
    os.makedirs(output_dir, exist_ok=True)
    pair_key = resolve_kraken_pair(pair)

    checkpoint_file = os.path.join(output_dir, f"{pair}-trades-checkpoint.json")
    fichier_sortie = os.path.join(output_dir, f"{pair}-kraken-{interval_min}m-brut.xlsx")

    start_dt = datetime.strptime(start_date, '%Y-%m-%d').replace(tzinfo=timezone.utc)
    end_dt = datetime.strptime(end_date, '%Y-%m-%d').replace(tzinfo=timezone.utc)
    end_ts_sec = end_dt.timestamp()

    all_trades = []
    since_ts = int(start_dt.timestamp() * 1_000_000_000)  # nanosecondes, attendu par /Trades

    # Reprise depuis un checkpoint existant si le script a été interrompu
    if os.path.exists(checkpoint_file):
        with open(checkpoint_file, 'r') as f:
            checkpoint = json.load(f)
        since_ts = checkpoint['since_ts']
        all_trades = checkpoint['trades']
        print(f"Reprise depuis le checkpoint : {len(all_trades)} trades déjà récupérés, "
              f"on continue depuis {since_ts}.")

    url = 'https://api.kraken.com/0/public/Trades'
    calls_since_checkpoint = 0

    print(f"Démarrage/poursuite du téléchargement tick-par-tick pour {pair}...")
    print("Attention : sur plusieurs années, cela peut prendre plusieurs heures (rate limit Kraken).")

    while True:
        params = {'pair': pair, 'since': since_ts}
        try:
            response = requests.get(url, params=params)
            data = response.json()

            if data.get('error'):
                if any('Rate limit' in e for e in data['error']):
                    print("  Limite de requêtes atteinte, pause de 5 secondes...")
                    time.sleep(5)
                    continue
                else:
                    print(f"  Erreur API : {data['error']}")
                    break

            trades = data['result'][pair_key]
            if not trades:
                break

            all_trades.extend(trades)
            last_trade_ts_sec = float(trades[-1][2])
            print(f"  Progression : {datetime.fromtimestamp(last_trade_ts_sec, tz=timezone.utc)} "
                  f"({len(all_trades)} trades cumulés)")

            if last_trade_ts_sec >= end_ts_sec:
                break

            new_since_ts = int(data['result']['last'])
            if new_since_ts == since_ts:
                # Sécurité anti-boucle infinie si Kraken renvoie deux fois le même curseur
                break
            since_ts = new_since_ts

            calls_since_checkpoint += 1
            if calls_since_checkpoint >= checkpoint_every:
                with open(checkpoint_file, 'w') as f:
                    json.dump({'since_ts': since_ts, 'trades': all_trades}, f)
                calls_since_checkpoint = 0
                print(f"  Checkpoint sauvegardé ({len(all_trades)} trades).")

            time.sleep(1.5)  # respect strict du rate limit public de Kraken

        except Exception as e:
            print(f"  Erreur réseau : {e}. Nouvelle tentative dans 5s...")
            time.sleep(5)

    if not all_trades:
        print("Aucune donnée récupérée.")
        return

    print(f"\nTéléchargement terminé ({len(all_trades)} transactions). "
          f"Construction des bougies {interval_min}m...")

    # Format réel de l'endpoint REST /Trades (7 éléments) :
    # [price, volume, time, side ('b'/'s'), order_type ('m'/'l'), misc, trade_id]
    df = pd.DataFrame(all_trades, columns=[
        'price', 'volume', 'time', 'side', 'order_type', 'misc', 'trade_id'
    ])
    df['price'] = df['price'].astype(float)
    df['volume'] = df['volume'].astype(float)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df = df.set_index('time')

    rule = f'{interval_min}min'
    # Fenêtres sans transaction -> NaN pour l'OHLC (pas de prix observé, donc pas de comblement ici)
    ohlc = df['price'].resample(rule).ohlc()
    # Fenêtres sans transaction -> 0 pour le volume (fait réel, pas un comblement)
    volume = df['volume'].resample(rule).sum()

    df_final = pd.concat([ohlc, volume], axis=1).reset_index()

    start_naive = start_dt.replace(tzinfo=None)
    end_naive = end_dt.replace(tzinfo=None)
    df_final = df_final[(df_final['time'] >= start_naive) & (df_final['time'] <= end_naive)]

    df_final = df_final.rename(columns={'time': 'date'})
    df_final['timestamp'] = df_final['date'].astype('int64') // 10**9
    df_final = df_final[['timestamp', 'date', 'open', 'high', 'low', 'close', 'volume']]

    n_missing = df_final['close'].isna().sum()
    print(f"Génération du fichier Excel ({len(df_final)} lignes, dont "
          f"{n_missing} fenêtres sans transaction, laissées à NaN)...")
    df_final.to_excel(fichier_sortie, index=False)
    print(f"Opération réussie ! Fichier sauvegardé : {fichier_sortie}")

    # Nettoyage du checkpoint une fois le fichier final généré avec succès
    if os.path.exists(checkpoint_file):
        os.remove(checkpoint_file)


if __name__ == "__main__":
    output_path = 'C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Collect_data/'

    download_and_reconstruct_kraken_ohlc(
        pair='USDCUSD',
        start_date='2021-12-31',
        end_date='2025-04-02',
        output_dir=output_path,
        interval_min=5
    )