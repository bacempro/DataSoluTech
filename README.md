
# Migration de données CSV vers MongoDB (Docker/AWS-ready)

Ce dépôt contient un script Python qui migre un dataset de santé (CSV) vers MongoDB.
Il applique des **transformations contrôlées**, crée un **index composé unique** pour assurer l'**idempotence**,
et propose un mode **upsert** pour réexécuter la migration sans doublons.

---

## 🎯 Objectif
- Charger un CSV volumineux dans MongoDB de manière **reproductible**.
- **Nettoyer/normaliser** certaines colonnes et **typer** les champs.
- Empêcher les doublons grâce à une **clé naturelle** + **index unique**.
- Permettre des **réexécutions sûres** via **upsert**.

---

## 🧱 Schéma logique (document MongoDB)

| Champ (Mongo)        | Source CSV              | Type cible        | Règle de transformation |
|----------------------|-------------------------|-------------------|-------------------------|
| `name`               | `Name`                  | string            | `lower()`              |
| `age`                | `Age`                   | int               | coercition → int       |
| `gender`             | `Gender`                | string            | `lower()`              |
| `blood_type`         | `Blood Type`            | string            | `lower()`              |
| `medical_condition`  | `Medical Condition`     | string            | trim                   |
| `date_of_admission`  | `Date of Admission`     | datetime (00:00)  | parse `dayfirst=True` + normalisation date-only |
| `doctor`             | `Doctor`                | string            | trim                   |
| `hospital`           | `Hospital`              | string            | `lower()`              |
| `insurance_provider` | `Insurance Provider`    | string            | trim                   |
| `billing_amount`     | `Billing Amount`        | float             | coercition → float     |
| `room_number`        | `Room Number`           | string            | conserver tel quel     |
| `admission_type`     | `Admission Type`        | string            | trim                   |
| `discharge_date`     | `Discharge Date`        | datetime (00:00)  | parse + normalisation  |
| `medication`         | `Medication`            | string            | trim                   |
| `test_results`       | `Test Results`          | string            | trim                   |
| `ingested_at`        | —                       | datetime (UTC)    | défini à l’insertion   |
| `last_modified_at`   | —                       | datetime (UTC)    | défini à chaque upsert |
| `source`             | —                       | string            | `csv_migration_v2`     |

> Les colonnes CSV attendues (sensible à la casse) :  
> `['Name','Age','Gender','Blood Type','Medical Condition','Date of Admission','Doctor','Hospital','Insurance Provider','Billing Amount','Room Number','Admission Type','Discharge Date','Medication','Test Results']`

---

## 🔑 Clé naturelle & index

- **Clé naturelle** choisie : (`name`, `gender`, `blood_type`, `date_of_admission`, `hospital`)
- Tous les champs de la clé sont **normalisés** (lowercase) et la date est **au jour** (00:00:00)
- **Index composé unique** pour empêcher les doublons :
  ```python
  collection.create_index(
      [("name", 1), ("gender", 1), ("blood_type", 1), ("date_of_admission", 1), ("hospital", 1)],
      unique=True,
      name="uniq_admission",
  )
  ```

**Pourquoi un index ?**  
Un index accélère les recherches (évite le scan complet) et ici **garantit l’unicité** des admissions.
Sans index unique, une réexécution du script pourrait insérer des doublons.

---

## ⚙️ Fonctionnement du script

Script principal : `migrate_to_mongo_upsert.py`

- Lecture streaming du CSV en **chunks** (`--chunksize`), transformation ligne par ligne.
- **Dry-run** pour prévisualiser les documents transformés sans écrire en base.
- **Upsert** par défaut : réexécutions idempotentes (mise à jour si déjà présent, insertion sinon).
- **Index** : `--create-indexes` crée l’index unique une fois.
- **Journaux** : niveau contrôlable via `--log-level` (INFO par défaut).

---

## 📦 Prérequis & installation

- Python 3.10+ (fonctionne très bien dans un environnement conda)
- MongoDB accessible (local ou distant)
- Installer les dépendances :
  ```bash
  pip install -r requirements.txt
  ```

> Variante conda :  
> `conda install pandas pymongo` puis `pip install python-dotenv` si besoin.

---

## ▶️ Exemples d’exécution

### 1) Prévisualisation (dry-run)
```bash
python migrate_to_mongo_upsert.py --csv /chemin/healthcare_dataset.csv --dry-run
```

### 2) Création de l’index (une fois) + upsert
```bash
python migrate_to_mongo_upsert.py   --csv /chemin/healthcare_dataset.csv   --mongo-uri "mongodb://localhost:27017"   --db healthcare --collection patients   --create-indexes --upsert
```

### 3) Réexécuter en toute sécurité (idempotent)
```bash
python migrate_to_mongo_upsert.py --csv /chemin/healthcare_dataset.csv --upsert
```

### 4) Insérer sans upsert (non recommandé ici)
```bash
python migrate_to_mongo_upsert.py --csv /chemin/healthcare_dataset.csv --no-upsert
```

---

## 🔐 Variables d’environnement (.env pris en charge)
Le script charge `.env` si présent (via `python-dotenv`) :
```
CSV_PATH=/chemin/healthcare_dataset.csv
MONGO_URI=mongodb://localhost:27017
MONGO_DB=healthcare
MONGO_COLLECTION=patients
LOG_LEVEL=INFO
```
> Chaque option peut aussi être passée via la ligne de commande.

---

## 🧪 Tests & qualité
- Ajoutez des tests unitaires pour `transform_row` (types, normalisation) et un test d’intégration simple avec une base éphémère (Mongo en container).
- Détectez les lignes incomplètes : le script les **ignore** en les **loggant**.

---

## 🐳 Et avec Docker ? (aperçu)
Un `requirements.txt` permet d’installer les dépendances **dans l’image** :
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY migrate_to_mongo_upsert.py .
CMD ["python", "migrate_to_mongo_upsert.py", "--csv", "/data/healthcare_dataset.csv", "--create-indexes", "--upsert"]
```
Vous monterez votre CSV dans `/data` via `-v` ou `Docker Compose`.

---

## ❗Points d’attention
- **Clé naturelle** : si la logique évolue (ex. ajouter `room_number`), mettre à jour **l’index** et **le filtre d’upsert**.
- **Fuseaux horaires** : les dates sont stockées en naïf (00:00). Si besoin de TZ-aware, on adaptera.
- **Concurrence** : en cas d’écritures concurrentes multiples, ajouter des retries sur codes d’erreur spécifiques.
- **Données manquantes** : les lignes sans clé naturelle complète sont ignorées (voir logs).

---

## 📚 Commandes utiles MongoDB
```javascript
// Vérifier l'index
db.patients.getIndexes()

// Compter les documents
db.patients.countDocuments({})

// Rechercher par date d'admission
db.patients.find({ date_of_admission: ISODate("2019-08-20T00:00:00Z") }).limit(5)
```

---

## Licence
Usage pédagogique.
