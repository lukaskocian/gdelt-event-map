# GDELT `events` — attribute glossary

Reference for the GDELT 2.0 `events` table columns, with Czech descriptions. The
**Used** column marks attributes this project actually pulls (see `gdelt_ingest.sql`)
and their canonical name in our repo (Neon / Python `snake_case`). Naming rule:
`data-pipeline/../at_names.txt`.

Country-code systems differ: `ActionGeo_CountryCode` is **FIPS 10-4**; the actor
`*CountryCode` fields are **CAMEO** country/nationality codes — they do **not** join
`country_baseline` (which is keyed by FIPS).

## Event core

| GDELT attribute | Popis (CZ) | Used → our name |
|---|---|---|
| `GlobalEventID` | Unikátní ID události v GDELT databázi. | ✅ `global_event_id` (PK) |
| `DateAdded` | Časová značka (YYYYMMDDHHMMSS), kdy byla událost přidána do GDELT. | ✅ `date_added` |
| `AvgTone` | Průměrný tón souvisejících článků; záporné = negativní, kladné = pozitivní. | ✅ `avg_tone` |
| `GoldsteinScale` | Skóre dopadu typu události od −10 (silně konfliktní) do +10 (kooperativní). | ✅ `goldstein_scale` |
| `EventCode` | Nejpodrobnější CAMEO kód typu události; co se mezi aktéry stalo. | ✅ `event_code` |
| `SourceURL` | URL prvního článku, který událost zmínil. | ✅ `source_url` |

## Action geography (místo, kde se akce odehrála)

| GDELT attribute | Popis (CZ) | Used → our name |
|---|---|---|
| `ActionGeo_FullName` | Plný textový název místa události. | ✅ `action_geo_full_name` |
| `ActionGeo_Type` | Úroveň geografického rozlišení místa akce. | ✅ `action_geo_type` |
| `ActionGeo_CountryCode` | **FIPS** kód země, kde se událost odehrála. | ✅ `action_geo_country_code` |
| `ActionGeo_Lat` | Zeměpisná šířka místa události. | ✅ `action_geo_lat` |
| `ActionGeo_Long` | Zeměpisná délka místa události. | ✅ `action_geo_long` |
| `ActionGeo_FeatureID` | Identifikátor geografického prvku místa události. | — |
| `ActionGeo_ADM1Code` | Kód první administrativní úrovně místa události. | — |
| `ActionGeo_ADM2Code` | Kód druhé administrativní úrovně místa události. | — |

## Actor 1 (zdroj / iniciátor akce)

| GDELT attribute | Popis (CZ) | Used → our name |
|---|---|---|
| `Actor1Name` | Textový název prvního aktéra rozpoznaný v článku. | ✅ `actor1_name` |
| `Actor1Geo_FullName` | Plný textový název geolokace prvního aktéra. | ✅ `actor1_geo_full_name` |
| `Actor1CountryCode` | **CAMEO** kód země nebo národnosti prvního aktéra. | ✅ `actor1_country_code` |
| `Actor1Code` | Kompozitní CAMEO kód prvního aktéra. | — |
| `Actor1Type1Code` | Primární typ prvního aktéra (vláda, policie, firma, média…). | — |
| `Actor1Geo_CountryCode` | FIPS kód země geolokace prvního aktéra. | — |
| `Actor1Geo_Lat` / `Actor1Geo_Long` | Zeměpisná šířka/délka geolokace prvního aktéra. | — |
| `Actor1Geo_FeatureID` | Identifikátor geografického prvku geolokace prvního aktéra. | — |
| `Actor1Geo_ADM1Code` / `Actor1Geo_ADM2Code` | Kódy administrativních úrovní geolokace prvního aktéra. | — |

## Actor 2 (cíl / příjemce akce)

| GDELT attribute | Popis (CZ) | Used → our name |
|---|---|---|
| `Actor2Name` | Textový název druhého aktéra rozpoznaný v článku. | ✅ `actor2_name` |
| `Actor2Geo_FullName` | Plný textový název geolokace druhého aktéra. | ✅ `actor2_geo_full_name` |
| `Actor2CountryCode` | **CAMEO** kód země nebo národnosti druhého aktéra. | ✅ `actor2_country_code` |
| `Actor2Code` | Kompozitní CAMEO kód druhého aktéra. | — |
| `Actor2Type1Code` | Primární typ druhého aktéra (vláda, policie, firma, civilisté…). | — |
| `Actor2Geo_CountryCode` | FIPS kód země geolokace druhého aktéra. | — |
| `Actor2Geo_Lat` / `Actor2Geo_Long` | Zeměpisná šířka/délka geolokace druhého aktéra. | — |
| `Actor2Geo_FeatureID` | Identifikátor geografického prvku geolokace druhého aktéra. | — |
| `Actor2Geo_ADM1Code` / `Actor2Geo_ADM2Code` | Kódy administrativních úrovní geolokace druhého aktéra. | — |

---

_Note: descriptions reconstructed from the project's attribute notes. If your own
highlighted table lists columns not here (GDELT `events` has ~60), paste them in the
matching section — same three-column shape._
