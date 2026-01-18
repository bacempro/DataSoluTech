# Migration de données CSV vers MongoDB (Docker/Compose + Reporting, AWS-ready)

Ce dépôt contient un script Python qui migre un dataset de santé (CSV) vers MongoDB.
Il applique des **transformations contrôlées**, crée un **index composé unique** pour assurer l'**idempotence**, propose un mode **upsert** pour réexécuter la migration sans doublons, et génère un **rapport d’exécution** persistant.

---

## 🎯 Objectif

* Charger un CSV (potentiellement volumineux) dans MongoDB de manière **reproductible**.
* **Nettoyer/normaliser** certaines colonnes et **typer** les champs.
* Empêcher les doublons grâce à une **clé naturelle** + **index unique** + **upsert**.
* **Tracer les exécutions** dans un `report.txt` (lignes du CSV, doublons, lignes incomplètes, documents écrits).

---

## 🧱 Schéma logique (document MongoDB)

| Champ (Mongo)        | Source CSV           | Type cible       | Règle de transformation                         |
| -------------------- | -------------------- | ---------------- | ----------------------------------------------- |
| `name`               | `Name`               | string           | `lower()`                                       |
| `age`                | `Age`                | int              | coercition → int                                |
| `gender`             | `Gender`             | string           | `lower()`                                       |
| `blood_type`         | `Blood Type`         | string           | `lower()`                                       |
| `medical_condition`  | `Medical Condition`  | string           | trim                                            |
| `date_of_admission`  | `Date of Admission`  | datetime (00:00) | parse `dayfirst=True` + normalisation date-only |
| `doctor`             | `Doctor`             | string           | trim                                            |
| `hospital`           | `Hospital`           | string           | `lower()`                                       |
| `insurance_provider` | `Insurance Provider` | string           | trim                                            |
| `billing_amount`     | `Billing Amount`     | float            | coercition → float                              |
| `room_number`        | `Room Number`        | string           | conserver tel quel                              |
| `admission_type`     | `Admission Type`     | string           | trim                                            |
| `discharge_date`     | `Discharge Date`     | datetime (00:00) | parse + normalisation                           |
| `medication`         | `Medication`         | string           | trim                                            |
| `test_results`       | `Test Results`       | string           | trim                                            |
| `ingested_at`        | —                    | datetime (UTC)   | défini à l’insertion                            |
| `last_modified_at`   | —                    | datetime (UTC)   | défini à chaque upsert                          |
| `source`             | —                    | string           | `csv_migration_v2`                              |

> Colonnes CSV attendues (sensible à la casse) :
> `['Name','Age','Gender','Blood Type','Medical Condition','Date of Admission','Doctor','Hospital','Insurance Provider','Billing Amount','Room Number','Admission Type','Discharge Date','Medication','Test Results']`

---

## 🔑 Clé naturelle & index

* **Clé naturelle** choisie : (`name`, `gender`, `blood_type`, `date_of_admission`, `hospital`).
* Tous les champs de la clé sont **normalisés** (lowercase) et la date est **au jour** (00:00:00).
* **Index composé unique** pour empêcher les doublons :

```python
collection.create_index(
    [("name", 1), ("gender", 1), ("blood_type", 1), ("date_of_admission", 1), ("hospital", 1)],
    unique=True,
    name="uniq_admission",
)
```

**Pourquoi un index ?**

* Accélère les recherches (évite le scan complet).
* **Garantit l’unicité** des admissions côté base. Sans index unique, une réexécution pourrait insérer des doublons.

---

## ⚙️ Fonctionnement du script

Script principal : **`app/migrate_to_mongo.py`**

* Lecture streaming du CSV en **chunks** (`--chunksize`), transformation ligne par ligne.
* **Dry-run** pour prévisualiser sans écrire en base.
* **Upsert** par défaut : réexécutions idempotentes (mise à jour si déjà présent, insertion sinon).
* **Index** : `--create-indexes` crée l’index unique (à lancer au moins une fois).
* **Reporting** : à la fin de chaque exécution (hors `--dry-run`), appende une ligne à `report.txt` avec :

  * `total_rows` (lignes du CSV), `duplicates_in_csv` (doublons trouvés via la clé naturelle **dans le CSV**),
  * `missing_key_rows` (lignes sans clé naturelle complète), `upserted_or_modified` (documents insérés/modifiés).

Exemple de ligne dans le rapport :

```
[2026-01-18T15:42:10Z] csv=healthcare_dataset.csv total_rows=1000 duplicates_in_csv=7 missing_key_rows=2 upserted_or_modified=991
```

---

## 📦 Prérequis & installation

* Python 3.10+
* MongoDB local ou distant
* Installation des dépendances Python (exécution locale hors Docker) :

```bash
pip install -r requirements.txt
```

> Variante conda : `conda install pandas pymongo` puis `pip install python-dotenv`.

---

## ▶️ Exemples d’exécution (local)

1. **Prévisualisation (dry-run)**

```bash
python app/migrate_to_mongo.py --csv /chemin/healthcare_dataset.csv --dry-run
```

2. **Création de l’index + upsert**

```bash
python app/migrate_to_mongo.py \
  --csv /chemin/healthcare_dataset.csv \
  --mongo-uri "mongodb://localhost:27017" \
  --db healthcare --collection patients \
  --create-indexes --upsert
```

3. **Réexécuter en toute sécurité (idempotent)**

```bash
python app/migrate_to_mongo.py --csv /chemin/healthcare_dataset.csv --upsert
```

4. **Insérer sans upsert (non recommandé ici)**

```bash
python app/migrate_to_mongo.py --csv /chemin/healthcare_dataset.csv --no-upsert
```

---

## 🐳 Docker & Docker Compose (solution complète + permissions minimales)

### Arborescence

```
healthcare-mongo-migration/
├─ .env
├─ docker-compose.yml
├─ data/                          # vos CSV (montés en lecture seule)
│  └─ healthcare_dataset_subset.csv
├─ docker/
│  └─ mongo-init/
│     └─ 001-create-app-user.sh   # création utilisateur applicatif (RBAC)
└─ app/
   ├─ Dockerfile                  # image du loader (non-root)
   ├─ requirements.txt
   └─ migrate_to_mongo.py
```

### Choix d’architecture

* **mongo** : base MongoDB (image officielle), volume nommé `mongo_data` pour la persistance.
* **reports-init** : conteneur éphémère (busybox) qui **chown** le volume nommé `reports_data` vers l’UID/GID de l’utilisateur applicatif (ex. 10001:10001). Il s’exécute **une seule fois** au démarrage.
* **loader** : conteneur Python **non-root** (UID/GID fixés) qui lit les CSV en bind-mount **en lecture seule** et écrit le rapport dans le volume nommé (`/reports/report.txt`).

### Pourquoi ce design ?

* **Permissions minimales** : le process applicatif n’a pas de privilèges root et n’écrit pas sur l’hôte.
* **Lisibilité & portabilité** : les CSV restent accessibles côté hôte, le rapport persiste dans un volume Docker.
* **Séparation des rôles** : un init minimal fait l’opération d’ownership une fois, le loader reste non-root.

### Lancement

```bash
docker compose build
docker compose up
```

* Au **premier démarrage** :

  * `mongo` initialise l’admin root et lance le script d’init pour créer l’utilisateur applicatif (RBAC).
  * `reports-init` prépare le volume `reports_data` (ownership 10001:10001).
  * `loader` attend que Mongo soit **healthy**, crée l’index si demandé, charge les données et écrit dans le rapport.

* **Réexécutions** :

  * Relancer `docker compose up` rejoue le chargement en mode **idempotent** (pas de doublons grâce à l’index + upsert).

### Consulter le rapport (one-liner fiable)

Fonctionne même pendant `docker compose up` :

```bash
docker compose run --rm --no-deps reports-init sh -lc 'tail -n 50 /reports/report.txt || echo "No report yet at /reports/report.txt"'
```

### Copier le rapport sur l’hôte (optionnel)

```bash
docker compose run --rm --no-deps -v reports_data:/reports -v "$PWD":/host busybox sh -lc 'cp /reports/report.txt /host/'
```
