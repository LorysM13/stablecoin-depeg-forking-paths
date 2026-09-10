# ==============================================================================
#---- Packages ----
# ==============================================================================

library(readxl)
library(readr)
library(data.table)
library(purrr)
library(dplyr)
library(lubridate)
library(xts)
library(highfrequency)
library(evd)    
library(kableExtra)
library(ggplot2)
library(tidyr)
library(patchwork)

# Variables globales
base_dir = "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Results"
raw_dir = "C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data"
stablecoins = c("DAI", "USDC", "USDT")
baseline_file = "path_005.csv" #Chemin representant ancienne methodo

# Variables temporelles
date_debut = as.POSIXct("2022-01-01 00:00:00", tz = "UTC")#Debut de l'echantillon
date_fin = as.POSIXct("2025-04-01 00:00:00", tz = "UTC")#Fin echantillon
M = 287 # Constante pour la détection des sauts (288 observations par jour - 1), convention article Boudt et al.

# ==============================================================================
# ---- Preparation des donnees ---- 
# ==============================================================================

df_btc = read_excel("C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/BTC-USD-5m.xlsx")
df_btc = df_btc[order(df_btc$Date), ] #Verification trie par date
df_btc$Return = c(NA, diff(log(df_btc$Close)))
df_btc = df_btc[-1,]

df_usdt = read_excel("C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/USDT-USD-5m.xlsx")
df_usdt = df_usdt[order(df_usdt$date), ] #Verification trie par date
df_usdt = df_usdt %>%
  filter(date >= as.Date("2022-01-01"),
         date <= as.Date("2025-04-01"))

df_usdc = read_excel("C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/USDC-USD-5m.xlsx")
df_usdc = df_usdc[order(df_usdc$date), ] #Verification trie par date
df_usdc = df_usdc %>%
  filter(date >= as.Date("2022-01-01"),
         date <= as.Date("2025-04-01"))

df_dai = read_excel("C:/Users/lorys/OneDrive - Université de Namur/2025-2026/Mémoire/Data/Raw_data/DAI-USD-5m.xlsx")
df_dai = df_dai[order(df_dai$date), ] #Verification trie par date
df_dai = df_dai %>%
  filter(date >= as.Date("2022-01-01"),
         date <= as.Date("2025-04-01"))

# ==============================================================================
# ---- Stats descriptives ---- 
# ==============================================================================


completer_dates_et_stats = function(df, nom_coin) {
  df$date = as.POSIXct(df$date, tz = "UTC")#S'assurer date bon format
  
  dates_completes = data.frame(
    date = seq(from = date_debut, to = date_fin, by = "5 min")
  )
  
  df_complet = dates_completes %>% left_join(df, by = "date")
  
  na_finaux = sum(is.na(df_complet$close))
  pourcentage_manquant = round((na_finaux / nrow(df_complet)) * 100, 4)
  
  stats = data.frame(
    Stablecoin                 = nom_coin,
    "Total observations"       = nrow(df_complet),
    "Total valeurs manquantes" = na_finaux,
    "% de valeurs manquantes"  = pourcentage_manquant
  )
  
  list(df = df_complet, stats = stats)
}

res_usdt = completer_dates_et_stats(df_usdt, "USDT")
res_usdc = completer_dates_et_stats(df_usdc, "USDC")
res_dai  = completer_dates_et_stats(df_dai,  "DAI")

df_usdt = res_usdt$df
df_usdc = res_usdc$df
df_dai  = res_dai$df

#tableau global valeurs manquantes
df_stats_manquantes = bind_rows(res_usdt$stats, res_usdc$stats, res_dai$stats)

df_stats_manquantes %>%
  kable("html", align = "c",
        caption = "Nombre total de valeurs manquantes (trous temporels inclus)",
        col.names = c("Stablecoin", "Total observations",
                      "Total valeurs manquantes", "% de valeurs manquantes")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

#Tableau prix de cloture 

close_df = data.frame(
  Date = df_usdt$date,
  USDT = df_usdt$close,
  DAI  = df_dai$close,
  USDC = df_usdc$close
)
#Resume tableau cloture
summary_close_df = data.frame(
  "Stablecoin" = c("USDT", "USDC", "DAI"),
  "Mean"    = round(c(mean(close_df$USDT, na.rm = TRUE),
                      mean(close_df$USDC, na.rm = TRUE),
                      mean(close_df$DAI,  na.rm = TRUE)), 5),
  "Std.Dev" = round(c(sd(close_df$USDT, na.rm = TRUE),
                      sd(close_df$USDC, na.rm = TRUE),
                      sd(close_df$DAI,  na.rm = TRUE)), 5),
  "Median"  = round(c(median(close_df$USDT, na.rm = TRUE),
                      median(close_df$USDC, na.rm = TRUE),
                      median(close_df$DAI,  na.rm = TRUE)), 5),
  "Min"     = round(c(min(close_df$USDT, na.rm = TRUE),
                      min(close_df$USDC, na.rm = TRUE),
                      min(close_df$DAI,  na.rm = TRUE)), 5),
  "Max"     = round(c(max(close_df$USDT, na.rm = TRUE),
                      max(close_df$USDC, na.rm = TRUE),
                      max(close_df$DAI,  na.rm = TRUE)), 5),
  "Observations" = c(length(close_df$USDT), length(close_df$USDC), length(close_df$DAI))
)

summary_close_df %>%
  kable("html", align = "c", caption = "Statistiques descriptives des prix de cloture (5 min)") %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

#Tableau volumes d'echange
#Les NA correspondent a une absence reelle de donnees recues de l'API, on les met a 0
df_usdt$volume[is.na(df_usdt$volume)] = 0
df_usdc$volume[is.na(df_usdc$volume)] = 0
df_dai$volume[is.na(df_dai$volume)] = 0

volume_df = data.frame(
  Date = df_usdt$date,
  USDT = df_usdt$volume,
  DAI  = df_dai$volume,
  USDC = df_usdc$volume
)

df_volume_summary = data.frame(
  "Stablecoin" = c("USDT", "USDC", "DAI"),
  "Mean" = round(c(mean(volume_df$USDT), mean(volume_df$USDC), mean(volume_df$DAI)), 2),
  "Zero ratio" = paste0(round(c(mean(volume_df$USDT == 0) * 100,
                                mean(volume_df$USDC == 0) * 100,
                                mean(volume_df$DAI  == 0) * 100), 2), " %"),
  "Min"   = round(c(min(volume_df$USDT), min(volume_df$USDC), min(volume_df$DAI)), 2),
  "Max"   = round(c(max(volume_df$USDT), max(volume_df$USDC), max(volume_df$DAI)), 2),
  "Total" = round(c(sum(volume_df$USDT), sum(volume_df$USDC), sum(volume_df$DAI)), 2)
)

df_volume_summary %>%
  kable("html", align = "c", caption = "Statistiques descriptives des volumes d'echange (5 min)") %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ==============================================================================
# ---- Détection de jumps sur BTC ---- 
# ==============================================================================

#Calcul Bipower variation
df_btc = df_btc %>% filter(format(Date, "%H:%M:%S") != "00:00:00") #Suppression heures egales a minuit car spotVol ne donne pas la valeur pour minuit

T = nrow(df_btc) / M

#Fonction permetant de calculer le coefficient f_hat
f_hat_calculation_function = function(df){
  xts_df = xts(df$Close, order.by = df$Date)
  
  #Calcul f_hat (periodic component of intra-day volatility)
  spot_vol= spotVol(
    data = xts_df,
    method = "detPer",
    est = "TML",
    alignBy = "minutes",
    alignPeriod = 5,
    marketOpen = "00:00:00",
    marketClose = "23:59:59",
    tz = "UTC"
  )
  f_ti= spot_vol$periodic
  validation = sum(f_ti^2) / M
  if(validation == 1){
    #Creation dataframe fti
    df_fti = data.frame(
      Hour = format(as.POSIXct(index(f_ti)), "%H:%M:%S"),
      f_ti = coredata(f_ti)
    )
    return(df_fti) 
  }
  else{
    stop("Erreur dans le calcul de f_ti")
  }
}

jump_detection_function = function(df, df_fti){
  results = data.frame()
  T = nrow(df) / M
  pt = 0
  for (i in 1:T) {
    start_idx = 1 + pt
    end_idx = min(M + pt, nrow(df))
    temp_df = df[start_idx:end_idx, ] %>% filter(!is.na(Date))
    returns = temp_df$Return
    n = length(returns)
    BV = (pi / 2) * sum(abs(returns[1:(n - 1)]) * abs(returns[2:n]))
    s_hat = sqrt((1 / (M - 1)) * BV)
    
    df_fti = df_fti %>%
      mutate(Hour = format(as.POSIXct(Hour, format = "%H:%M:%S"), "%H:%M:%S"))
    
    temp_df = temp_df %>%
      mutate(Hour = format(Date, "%H:%M:%S")) %>%
      left_join(df_fti, by = "Hour") %>%
      as.data.frame() %>%
      dplyr::select(-Hour) %>%
      mutate(jump_ti = abs(Return) / (s_hat * f_ti))
    
    results = rbind(results, temp_df)
    pt = pt + M
  }
  
  alphas = c(0.01, 0.0001)
  for (alpha in alphas) {
    Sn = 1 / sqrt(2 * log(M))
    Cn = sqrt(2 * log(M)) - log(pi) + (log(log(M))) / (2 * sqrt(2 * log(M)))
    threshold = qgumbel(p = 1 - alpha, loc = 0, scale = 1) * Sn + Cn
    if (alpha == 0.0001) {
      results = results %>% mutate(significant_large_jump = ifelse(jump_ti > threshold, 1, 0))
    } else {
      results = results %>% mutate(significant_jump = ifelse(jump_ti > threshold, 1, 0))
    }
  }
  results %>% mutate(day = as.Date(Date))
}

df_fti_btc = f_hat_calculation_function(df_btc)
df_jump_btc = jump_detection_function(df_btc, df_fti_btc)
btc_jumps_clean = df_jump_btc %>%
  select(Date, Return, jump_ti, significant_jump, significant_large_jump)

# ==============================================================================
# ---- Fonctions forking paths ---- 
# ==============================================================================
eventWindowCalculation = function(df){
  event_window_df = data.frame()
  for (n in seq_len(nrow(df))) {
    if (!is.na(df$Depeg_start[n]) && df$Depeg_start[n] == 1) {
      start_idx = df$Date[n]
      end_idx = df$Date[n] + lubridate::hours(4)
      event_window_df = bind_rows(event_window_df, df %>% filter(Date >= start_idx & Date <= end_idx))
    }
  }
  distinct(event_window_df)
}

build_regression_data = function(event_window, control_sample){
  
  # Attribution valeurs binaires a event_window
  df_event = event_window %>%
    mutate(is_depeg_period = 1, 
           jump = ifelse(!is.na(significant_jump) & significant_jump == 1, 1, 0)) 
  
  # Attribution valeurs binaires a control_sample
  df_control = control_sample %>%
    mutate(is_depeg_period = 0, 
           jump = ifelse(!is.na(significant_jump) & significant_jump == 1, 1, 0)) 
  
  # Fusion des deux df
  df_model = bind_rows(df_event, df_control) %>%
    select(Date, is_depeg_period, jump)
  
  return(df_model)
}

#Fonction de calcul des effets marginaux
#Reference Norton, Dowd & Maciejewski (2019)
compute_marginal_effect = function(df_regression) {
  
  p1 = mean(df_regression$jump[df_regression$is_depeg_period == 1])
  p0 = mean(df_regression$jump[df_regression$is_depeg_period == 0])
  n1 = sum(df_regression$is_depeg_period == 1)
  n0 = sum(df_regression$is_depeg_period == 0)
  
  #Application formule dans methodologie
  me = p1 - p0
  se_me = sqrt(p1 * (1 - p1) / n1 + p0 * (1 - p0) / n0)
  
  data.frame(
    P_event     = p1,
    P_control   = p0,
    ME          = me,
    SE_ME       = se_me,
    ME_CI_lower = me - 1.96 * se_me,
    ME_CI_upper = me + 1.96 * se_me
  )
}

analyse_single_path = function(file_path, btc_jumps_clean){   
  df_path = fread(file_path)
  df_path$Date = as.POSIXct(df_path$Date, format="%Y-%m-%d %H:%M:%S", tz="UTC") 
  df_merged = df_path %>% left_join(btc_jumps_clean, by = "Date") 
  
  # Si aucun depeg detecte
  if(sum(df_merged$Depeg_start, na.rm = TRUE) == 0){ 
    return(data.frame(
      Path = basename(file_path),
      Nbr_Depegs = 0,
      Bp_effect = NA_real_,
      AIC_p = Inf,
      Sigma_p = NA_real_,
      Nbr_Jumps_Dans_Fenetre = NA_integer_,
      N_obs = NA_integer_,
      N_event = NA_integer_,
      N_control = NA_integer_,
      P_event = NA_real_,
      P_control = NA_real_,
      ME = NA_real_,
      SE_ME = NA_real_,
      ME_CI_lower = NA_real_,
      ME_CI_upper = NA_real_
    ))
  }
  
  df_event_window = eventWindowCalculation(df_merged)
  
  df_control_sample = df_merged %>%
    filter(!(Date %in% df_event_window$Date))%>%
    filter(Depeg_serie == 0)
  
  #Appel fonction pour creer df pour regression
  df_regression = build_regression_data(df_event_window, df_control_sample)
  
  #Calcul nbr sauts dans event window
  nb_jump_dans_depeg = sum(df_regression$is_depeg_period == 1 & df_regression$jump == 1)
  
  #Calcul modele logistique
  modele_glm = glm(jump ~ is_depeg_period, data = df_regression, family = binomial)
  
  # Extraction coefficients
  aic_p = AIC(modele_glm)
  bp = coef(modele_glm)["is_depeg_period"]
  
  # Extraction de la Std. Error depuis le summary
  sigma_p = summary(modele_glm)$coefficients["is_depeg_period", "Std. Error"] 
  
  # Calcul des effets marginaux sur le meme echantillon de regression
  df_me = compute_marginal_effect(df_regression)
  
  #Return des deux tableaux
  return(cbind(
    data.frame(
      Path = basename(file_path),
      Nbr_Depegs = sum(df_merged$Depeg_start, na.rm = TRUE),
      Bp_effect = bp,
      AIC_p = aic_p, 
      Sigma_p = sigma_p,
      Nbr_Jumps_Dans_Fenetre = nb_jump_dans_depeg,
      N_obs = nrow(df_regression),
      N_event = nrow(df_event_window),
      N_control = nrow(df_control_sample),
      row.names = NULL
    ),
    df_me
  ))
}

calculate_forking_paths_statistics = function(df_all_paths_all_stablecoins){
  
  # On retire les chemins qui n'ont pas de dépeg (AIC infini ou Bp manquant)
  df_valid = df_all_paths_all_stablecoins %>%
    filter(AIC_p != Inf, !is.na(Bp_effect))
  
  result_by_stablecoin = df_valid %>%
    group_by(Stablecoin, sample_size) %>%
    mutate( 
      # Calcul des poids individuels pour chaque chemin
      # Le regroupement par sample_size est necessaire car l'AIC n'est comparable qu'entre modeles estimes sur un meme nombre d'observations
      min_aic = min(AIC_p),
      delta_aic = AIC_p - min_aic,
      divided_weight = exp(-delta_aic / 2),
      w_p = divided_weight / sum(divided_weight)
    ) %>%
    
    summarise(
      Nbr_valid_paths = n(),
      
      # Calcul de l'effet agrege B_star
      B_star = sum(w_p * Bp_effect),
      
      # Calcul de la variance agregee (Variance_star)
      Variance_star = (sum(w_p * sqrt(Sigma_p^2 + (B_star - Bp_effect)^2)))^2,
      
      # Calcul de l'intervalle de confiance a 95%
      CI_lower = B_star - 1.96 * sqrt(Variance_star) / sqrt(n()),
      CI_upper = B_star + 1.96 * sqrt(Variance_star) / sqrt(n()),
      
      .groups = "drop"
    )
  
  return(result_by_stablecoin)
}

calculate_EtC = function(df_all_paths_all_stablecoins, baseline_path_id, q = 0.9){
  
  #On garde que les chemins avec AIC possibles
  df_valid = df_all_paths_all_stablecoins %>%
    filter(AIC_p != Inf, !is.na(Bp_effect))
  
  resultats = list()
  
  for (coin in unique(df_valid$Stablecoin)) { #Pour chaque stablecoin unique dans les resultats
    
    df_coin = df_valid %>% filter(Stablecoin == coin) #On cree df avec uniquement les donnes du stablecoin
    
    ligne_ref = df_coin %>% filter(Path == baseline_path_id) #On recupere les donnees du chemin representant ancienne methodo
    
    b_star = ligne_ref$Bp_effect[1]
    
    signe = if (b_star >= 0) 1 else -1
    
    b_p_all = df_coin$Bp_effect * signe
    
    b_star_adj = b_star * signe
    
    mu_hat = mean(b_p_all) #Moyenne tous les chemins valides
    sd_hat = sd(b_p_all) #Ecart-type tous les chemins valides
    
    # Position du b* de reference dans la distribution gaussienne ajustee
    phi_b_star = pnorm(b_star_adj, mean = mu_hat, sd = sd_hat)
    
    # Seuil theta au niveau q (90e percentile des effets des chemins)
    theta = qnorm(q, mean = mu_hat, sd = sd_hat)
    phi_theta = q
    
    # OFO (Eq. 30) : indicatrice 1{b* > theta} -> 0 si b* est en-dessous du seuil
    indicatrice = as.numeric(b_star_adj > theta)
    OFO = ((phi_b_star - phi_theta) / (1 - phi_theta)) * indicatrice
    OFO = max(0, min(1, OFO))
    
    EtC = 1 - OFO
    
    resultats[[coin]] = data.frame(
      Stablecoin = coin,
      Baseline_path = baseline_path_id,
      B_reference = b_star,              
      Nbr_chemins_valides = nrow(df_coin),
      Moyenne_chemins = mu_hat * signe,
      Ecart_type_chemins = sd_hat,
      Percentile_b_star = phi_b_star,
      Seuil_theta_q90 = unname(theta) * signe,
      EtC = EtC
    )
  }
  bind_rows(resultats)
}

# ==============================================================================
# ---- Execution des fonctions sur l'ensemble des chemins ---- 
# ==============================================================================

final_results = list()

for (coin in stablecoins) {
  
  #Pointage vers le dossier du stablecoin
  coin_dir = file.path(base_dir, coin)
  
  #Recuperation automatique de tous les fichiers path_XXX.csv
  path_files = list.files(coin_dir, pattern = "^path_.*\\.csv$", full.names = TRUE)
  
  # map_dfr applique la fonction à chaque fichier et fusionne le tout en un seul dataframe
  coin_results = map_dfr(path_files, analyse_single_path, btc_jumps_clean = btc_jumps_clean)
  
  # On ajoute le nom du stablecoin au tableau
  coin_results$Stablecoin = coin
  
  final_results[[coin]] = coin_results
}

df_all_paths_all_stablecoins = bind_rows(final_results)

# ---- Fusion des metadonnees methodologiques ----
# Fonction va lire le fichier excel avec les operations qui varient selon les chemins pour les differents stablecoins
load_single_paths = function(base_dir, coin) {
  meta = fread(file.path(base_dir, coin, "paths_metadata.csv"))
  meta$Path = basename(meta$csv_path)
  meta$Stablecoin = coin
  return(meta)
}

# Execution du chargement de l'ensemble des fichiers paths pour les stablecoins
pathdata_all = map_dfr(stablecoins, ~load_single_paths(base_dir, .x))

#Ajoute au tableau contenant les resultats des stablecoins les operations des chemins
df_all_paths_all_stablecoins = df_all_paths_all_stablecoins %>%
  left_join(
    pathdata_all %>%
      select(Path, Stablecoin, missing_method, sample_size, threshold,
             minimal_duration, grouping_window),
    by = c("Path", "Stablecoin")
  )

# ---- Filtre resultats pour supprimer chemins aberrants -----

df_all_paths_sans_aberrants = df_all_paths_all_stablecoins %>%
  filter(is.na(Nbr_Jumps_Dans_Fenetre) | Nbr_Jumps_Dans_Fenetre > 0)

df_all_paths_all_stablecoins %>%
  group_by(Stablecoin) %>%
  summarise(
    Total = n(),
    Exclus = sum(AIC_p == Inf | is.na(Bp_effect)),
    Valides = Total - Exclus
  ) %>%
  print()

# ==============================================================================
# ---- Tableau quasi separation ---- 
# ==============================================================================

df_separation = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect), Nbr_Jumps_Dans_Fenetre == 0) %>%
  group_by(Bp_arrondi = round(Bp_effect, 2)) %>%
  summarise(
    Nbr_chemins = n(),
    Stablecoins = paste(sort(unique(Stablecoin)), collapse = ", "),
    Echantillons = paste(sort(unique(sample_size)), collapse = ", "),
    Seuils = paste(sort(unique(threshold)), collapse = ", "),
    Tailles_N_event = n_distinct(N_event),
    .groups = "drop"
  ) %>%
  arrange(desc(Nbr_chemins))

df_separation %>%
  kable("html", align = "c",
        caption = "Valeurs plancher des coefficients estimes sur les chemins sans saut observe",
        col.names = c("Valeur de bp", "Nbr chemins", "Stablecoins concernés",
                      "Echantillons", "Seuils", "Nbr de tailles de fenêtre distinctes")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 13) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ==============================================================================
# ---- Effet agrege b* : AIC par taille d'echantillon ----
# ==============================================================================

# ---- Version 1 : tous les chemins valides ----
df_stats_globales_complet = calculate_forking_paths_statistics(df_all_paths_all_stablecoins) %>%
  mutate(across(where(is.numeric), ~round(., 4))) %>%
  arrange(Stablecoin, sample_size)

df_stats_globales_complet %>%
  kable("html", align = "c",
        caption = "Effet agrege b* par taille d'echantillon (tous les chemins)",
        col.names = c("Stablecoin", "Echantillon", "Chemins valides",
                      "b*", "Variance", "IC inf. (95%)", "IC sup. (95%)")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 13) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE) %>%
  collapse_rows(columns = 1, valign = "middle")

# ---- Version 2 : chemins aberrants exclus ----
df_stats_globales_sans_aberrants = calculate_forking_paths_statistics(df_all_paths_sans_aberrants) %>%
  mutate(across(where(is.numeric), ~round(., 4))) %>%
  arrange(Stablecoin, sample_size)

df_stats_globales_sans_aberrants %>%
  kable("html", align = "c",
        caption = "Effet agrege b* par taille d'echantillon (chemins aberrants exclus)",
        col.names = c("Stablecoin", "Echantillon", "Chemins valides",
                      "b*", "Variance", "IC inf. (95%)", "IC sup. (95%)")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 13) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE) %>%
  collapse_rows(columns = 1, valign = "middle")

# ---- Comparaison cote a cote ----
df_comparaison = bind_rows(
  df_stats_globales_complet %>% mutate(Version = "Tous les chemins"),
  df_stats_globales_sans_aberrants %>% mutate(Version = "Chemins aberrants exclus")
) %>%
  relocate(Version, .after = Stablecoin) %>%
  arrange(Stablecoin, sample_size)

df_comparaison %>%
  kable("html", align = "c", caption = "Effet agrégé b* : comparaison avec et sans les chemins sans saut détecté",
        col.names = c("Stablecoin", "Version", "Echantillon", "Chemins valides", "b*", "Variance", "IC inf. (95%)", "IC sup. (95%)")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE) %>%
  collapse_rows(columns = 1, valign = "middle")

# ==============================================================================
# ---- Statistiques descriptives effets bp ----
# ==============================================================================

#Nombre de chemins valides et exclus
df_resume_paths = df_all_paths_all_stablecoins %>%
  group_by(Stablecoin) %>%
  summarise(
    Total = n(),
    Valides = sum(AIC_p != Inf & !is.na(Bp_effect)),
    Exclus = Total - Valides,
    .groups = "drop"
  )

df_resume_paths %>%
  kable("html", align = "c", caption = "Chemins valides et exclus par stablecoin",
        col.names = c("Stablecoin", "Total", "Valides", "Exclus")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

#Part des chemins valides sans aucun saut dans la fenetre
df_sans_jump = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect)) %>%
  group_by(Stablecoin) %>%
  summarise(
    Nbr_chemins_valides = n(),
    Nbr_chemins_sans_jump = sum(Nbr_Jumps_Dans_Fenetre == 0, na.rm = TRUE),
    Pct_sans_jump = round(100 * Nbr_chemins_sans_jump / Nbr_chemins_valides, 1),
    .groups = "drop"
  )

#Comparaison des effets bp selon la presence ou non d'un saut
df_bp_par_groupe = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect)) %>%
  mutate(Groupe = ifelse(Nbr_Jumps_Dans_Fenetre == 0, "Sans saut detecte", "Avec au moins 1 saut")) %>%
  group_by(Stablecoin, Groupe) %>%
  summarise(
    Nbr_chemins = n(),
    Bp_moyen = mean(Bp_effect, na.rm = TRUE),
    Bp_median = median(Bp_effect, na.rm = TRUE),
    Bp_min = min(Bp_effect, na.rm = TRUE),
    Bp_max = max(Bp_effect, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(Stablecoin) %>%
  mutate(Pct = round(100 * Nbr_chemins / sum(Nbr_chemins), 1)) %>%
  ungroup() %>%
  mutate(across(where(is.numeric), ~round(., 4))) %>%
  arrange(Stablecoin, desc(Groupe))

df_bp_par_groupe %>%
  kable("html", align = "c",
        caption = "Effets bp selon la presence ou l'absence d'un saut Bitcoin dans la fenetre",
        col.names = c("Stablecoin", "Groupe", "Nbr chemins", "bp moyen",
                      "bp median", "bp min", "bp max", "Part (%)")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE) %>%
  collapse_rows(columns = 1, valign = "middle")

#Statistiques descriptives globales des bp
df_stats_desc_bp = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect)) %>%
  group_by(Stablecoin) %>%
  summarise(
    Nbr_chemins = n(),
    Bp_moyen = mean(Bp_effect, na.rm = TRUE),
    Bp_median = median(Bp_effect, na.rm = TRUE),
    Bp_min = min(Bp_effect, na.rm = TRUE),
    Bp_max = max(Bp_effect, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~round(., 4)))

df_stats_desc_bp %>%
  kable("html", align = "c", caption = "Statistiques descriptives des effets bp",
        col.names = c("Stablecoin", "Nombre de chemins valides", "bp moyen",
                      "bp median", "bp min", "bp max")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ---- Histogramme de la distribution des bp ----
df_all_paths_all_stablecoins_valid = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect))

#Calcul des moyennes des Bp_effect de chaque stablecoin
df_means_bp = df_all_paths_all_stablecoins_valid %>%
  group_by(Stablecoin) %>%
  summarise(mean_bp = mean(Bp_effect, na.rm = TRUE))

ggplot(df_all_paths_all_stablecoins_valid, aes(x = Bp_effect, fill = Stablecoin)) +
  # geom_histogram cree la distribution. "bins" controle le nombre de barres
  geom_histogram(bins = 30, color = "black", alpha = 0.7) +
  # Ajout d'une ligne verticale pointillee rouge pour la moyenne
  geom_vline(data = df_means_bp, aes(xintercept = mean_bp), 
             color = "red", linetype = "dashed", linewidth = 1) +
  # On separe en 3 graphiques cote a cote (1 par stablecoin)
  facet_wrap(~ Stablecoin, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Distribution des effets estimés (Bp) à travers les différents chemins",
    x = "Coefficient estimé (Bp)",
    y = "Nombre de chemins"
  ) +
  scale_fill_manual(values = c("DAI" = "#1f4e79", "USDC" = "#2e7d32", "USDT" = "#d9534f")) +
  theme(
    legend.position = "none",
    strip.text = element_text(face = "bold", size = 14),
    plot.title = element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = element_text(hjust = 0.5, face = "italic", color = "gray40")
  )

# ==============================================================================
# ---- Effets marginaux ----
# ==============================================================================

df_me = df_all_paths_sans_aberrants %>%
  filter(AIC_p != Inf, !is.na(ME)) %>%
  group_by(Stablecoin) %>%
  summarise(
    Nbr_chemins = n(),
    ME_min      = round(min(ME), 4),
    ME_median   = round(median(ME), 4),
    ME_max      = round(max(ME), 4),
    P_control_moy = round(mean(P_control), 4),
    .groups = "drop"
  )

df_me %>%
  kable("html", align = "c",
        caption = "Etendue des effets marginaux a travers les chemins",
        col.names = c("Stablecoin", "Chemins", "EM minimum", "EM median",
                      "EM maximum", "P(saut) hors depeg")) %>%
  kable_styling(bootstrap_options = c("condensed"),
                full_width = TRUE, position = "center", font_size = 13) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ==============================================================================
# ---- Indicateur EtC ----
# ==============================================================================

# ---- Version 1 : Calcul tous les chemins valides ----
df_EtC_complet = calculate_EtC(df_all_paths_all_stablecoins, baseline_path_id = baseline_file, q = 0.9)

df_EtC_complet = df_EtC_complet %>%
  mutate(across(where(is.numeric), ~round(., 4))) #Arrondissement 4 chiffres

df_EtC_complet %>%
  kable("html", align = "c", caption = "Indicateur EtC : tous les chemins valides",
        col.names = c("Stablecoin", "Chemin de référence", "b (référence)", "Chemins valides", 
                      "Moyenne", "Écart-type", "Percentile b*", "Seuil θ (90e)", "EtC")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ---- Version 2 : Supression chemins "aberrants", garde chemins avec min un saut ----
df_EtC_sans_aberrants = calculate_EtC(df_all_paths_sans_aberrants, baseline_path_id = baseline_file, q = 0.9)

df_EtC_sans_aberrants = df_EtC_sans_aberrants %>% #Arrondissement 4 chiffres
  mutate(across(where(is.numeric), ~round(., 4)))

df_EtC_sans_aberrants %>%
  kable("html", align = "c", caption = "Indicateur EtC : chemins aberrants exclus",
        col.names = c("Stablecoin", "Chemin de référence", "b (référence)", "Chemins valides", 
                      "Moyenne", "Écart-type", "Percentile b*", "Seuil θ (90e)", "EtC")) %>%
  kable_styling(bootstrap_options = c("condensed"), full_width = TRUE, position = "center", font_size = 14) %>%
  row_spec(0, bold = TRUE, color = "black", background = "white") %>%
  column_spec(1, bold = TRUE)

# ==============================================================================
# SPECIFICATION CURVE
# ==============================================================================

# ---- Ajout des labels lisibles pour le graphique ----
ajouter_labels = function(df_source) {
  df_source %>%
    mutate(
      CI_lower    = Bp_effect - 1.96 * Sigma_p,
      CI_upper    = Bp_effect + 1.96 * Sigma_p,
      significant = CI_lower > 0 | CI_upper < 0,
      missing_method_lbl   = recode(missing_method,
                                    forward_fill = "Forward fill",
                                    interpolation = "Interpolation"),
      sample_size_lbl       = recode(sample_size,
                                     full = "Complet",
                                     first_half = "1re moitié",
                                     second_half = "2e moitié"),
      threshold_lbl          = recode(as.character(threshold),
                                      "05" = "0.5%", "10" = "1%",
                                      "15" = "1.5%", "25" = "2.5%"),
      minimal_duration_lbl   = paste0(minimal_duration, " min"),
      grouping_window_lbl    = paste0(grouping_window, " min")
    )
}

# ---- Dataset ----
df_spec_complet = df_all_paths_all_stablecoins %>%
  filter(AIC_p != Inf, !is.na(Bp_effect)) %>%
  ajouter_labels()

df_spec_sans_aberrants = df_all_paths_sans_aberrants %>%
  filter(AIC_p != Inf, !is.na(Bp_effect)) %>%
  ajouter_labels()

# ---- Fonction de trace chemin de reference ----
plot_spec_curve = function(data, coin_name, baseline_path_id = NULL, sous_titre_extra = "") {
  
  data = data %>% arrange(Bp_effect) %>% mutate(rank = row_number())
  
  a_une_reference = !is.null(baseline_path_id) &&
    (data %>% filter(Path == baseline_path_id) %>% nrow()) > 0
  rank_baseline = if (a_une_reference) data %>% filter(Path == baseline_path_id) %>% pull(rank) else NULL
  
  # --- Panneau superieur : b_p tries + IC 95% ---
  panel_top = ggplot(data, aes(x = rank, y = Bp_effect, color = significant)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey50")
  
  if (a_une_reference) {
    panel_top = panel_top +
      geom_vline(xintercept = rank_baseline, linetype = "dotted",
                 color = "black", linewidth = 0.7)
  }
  
  panel_top = panel_top +
    geom_pointrange(aes(ymin = CI_lower, ymax = CI_upper),
                    size = 0.2, fatten = 1, linewidth = 0.3) +
    scale_color_manual(values = c(`TRUE` = "#c0392b", `FALSE` = "grey65"),
                       labels = c(`TRUE` = "Significatif (95%)",
                                  `FALSE` = "Non significatif"),
                       name = NULL) +
    labs(title = paste0("Specification curve — ", coin_name),
         subtitle = paste0(
           nrow(data), " chemins valides", sous_titre_extra,
           if (a_une_reference) paste0(" | Chemin de référence : rang ", rank_baseline, "/", nrow(data)) else ""
         ),
         x = NULL, y = expression(hat(b)[p])) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(),
          legend.position = "top", panel.grid.minor = element_blank())
  
  # --- Panneau inferieur : matrice des choix methodologiques ---
  vars_lbl = c(missing_method_lbl = "Données manq.",
               sample_size_lbl     = "Échantillon",
               threshold_lbl       = "Seuil",
               minimal_duration_lbl = "Durée min.",
               grouping_window_lbl  = "Fenêtre group.")
  
  long_df = data %>%
    select(rank, all_of(names(vars_lbl))) %>%
    pivot_longer(-rank, names_to = "operation", values_to = "level") %>%
    mutate(operation = factor(vars_lbl[operation], levels = vars_lbl))
  
  panel_bottom = ggplot(long_df, aes(x = rank, y = level)) +
    geom_point(size = 0.8, color = "#1f4e79")
  
  if (a_une_reference) {
    panel_bottom = panel_bottom +
      geom_vline(xintercept = rank_baseline, linetype = "dotted",
                 color = "black", linewidth = 0.7)
  }
  
  panel_bottom = panel_bottom +
    facet_grid(operation ~ ., scales = "free_y", space = "free_y",
               switch = "y") +
    labs(x = "Chemins triés par effet estimé croissant", y = NULL) +
    theme_minimal(base_size = 9) +
    theme(strip.text.y.left = element_text(angle = 0, size = 8, hjust = 0),
          strip.placement = "outside",
          strip.background = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.minor = element_blank())
  
  panel_top / panel_bottom + plot_layout(heights = c(1, 2.2))
}

# ---- Generation graphique, chemins aberrants exclus ----
for (coin in stablecoins) {
  p = plot_spec_curve(df_spec_sans_aberrants %>% filter(Stablecoin == coin), coin,
                      baseline_path_id = baseline_file, sous_titre_extra = " (aberrants exclus)")
  ggsave(file.path(base_dir, paste0("spec_curve_", coin, "_final.png")),
         p, width = 10, height = 8, dpi = 300)
  print(p)
}

# ---- Generation graphique, tous les chemins, pour annexe ----
for (coin in stablecoins) {
  p = plot_spec_curve(df_spec_complet %>% filter(Stablecoin == coin), coin,
                      baseline_path_id = baseline_file, sous_titre_extra = " (tous chemins)")
  ggsave(file.path(base_dir, paste0("spec_curve_", coin, "_annexe.png")),
         p, width = 10, height = 8, dpi = 300)
  print(p)
}
