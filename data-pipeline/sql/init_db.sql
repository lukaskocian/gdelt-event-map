-- Schema for the GDELT Event Map pipeline (run on Neon.tech).

------------------------------------------------------------------------------
-- FACT TABLE: one row per event per 15-minute window. Pruned after 7 days.
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS articles_table_15_min (

    global_event_id BIGINT NOT NULL,
    time_window_15min TIMESTAMP WITH TIME ZONE NOT NULL,
    articles_count INTEGER NOT NULL,

    date_added TIMESTAMP WITH TIME ZONE,
    avg_tone REAL,
    goldstein_scale REAL,
    source_url TEXT,
    event_code VARCHAR(10),
    action_geo_full_name TEXT,
    action_geo_type SMALLINT,
    action_geo_country_code VARCHAR(3),
    action_geo_lat REAL,
    action_geo_long REAL,
    actor1_name TEXT,
    actor1_geo_full_name TEXT,
    actor1_country_code VARCHAR(3),
    actor2_name TEXT,
    actor2_geo_full_name TEXT,
    actor2_country_code VARCHAR(3),
    -- Idempotency: re-running the same window UPSERTs on the PK instead of duplicating.
    PRIMARY KEY (global_event_id, time_window_15min)
);

CREATE INDEX IF NOT EXISTS idx_time_window_15min
ON articles_table_15_min (time_window_15min);

CREATE INDEX IF NOT EXISTS idx_action_geo_country_code
ON articles_table_15_min (action_geo_country_code);

-- ---------------------------------------------------------------------------
-- DIMENSION: per-country normalization weight (can by updated by normalizer.py)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS country_baseline (
    country_code VARCHAR(3) PRIMARY KEY,   -- FIPS 10-4 code (GDELT ActionGeo_CountryCode)
    normalizing_coef REAL NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Seed every country with a neutral coefficient of 1.0 (placeholder). normalizer.py
INSERT INTO country_baseline (country_code, normalizing_coef) VALUES
    ('AA', 1.0),  -- Aruba
    ('AC', 1.0),  -- Antigua and Barbuda
    ('AE', 1.0),  -- United Arab Emirates
    ('AF', 1.0),  -- Afghanistan
    ('AG', 1.0),  -- Algeria
    ('AJ', 1.0),  -- Azerbaijan
    ('AL', 1.0),  -- Albania
    ('AM', 1.0),  -- Armenia
    ('AN', 1.0),  -- Andorra
    ('AO', 1.0),  -- Angola
    ('AQ', 1.0),  -- American Samoa
    ('AR', 1.0),  -- Argentina
    ('AS', 1.0),  -- Australia
    ('AU', 1.0),  -- Austria
    ('AV', 1.0),  -- Anguilla
    ('AY', 1.0),  -- Antarctica
    ('BA', 1.0),  -- Bahrain
    ('BB', 1.0),  -- Barbados
    ('BC', 1.0),  -- Botswana
    ('BD', 1.0),  -- Bermuda
    ('BE', 1.0),  -- Belgium
    ('BF', 1.0),  -- Bahamas
    ('BG', 1.0),  -- Bangladesh
    ('BH', 1.0),  -- Belize
    ('BK', 1.0),  -- Bosnia and Herzegovina
    ('BL', 1.0),  -- Bolivia
    ('BM', 1.0),  -- Burma (Myanmar)
    ('BN', 1.0),  -- Benin
    ('BO', 1.0),  -- Belarus
    ('BP', 1.0),  -- Solomon Islands
    ('BR', 1.0),  -- Brazil
    ('BT', 1.0),  -- Bhutan
    ('BU', 1.0),  -- Bulgaria
    ('BX', 1.0),  -- Brunei
    ('BY', 1.0),  -- Burundi
    ('CA', 1.0),  -- Canada
    ('CB', 1.0),  -- Cambodia
    ('CD', 1.0),  -- Chad
    ('CE', 1.0),  -- Sri Lanka
    ('CF', 1.0),  -- Congo (Brazzaville)
    ('CG', 1.0),  -- Congo (Kinshasa)
    ('CH', 1.0),  -- China
    ('CI', 1.0),  -- Chile
    ('CJ', 1.0),  -- Cayman Islands
    ('CK', 1.0),  -- Cocos (Keeling) Islands
    ('CM', 1.0),  -- Cameroon
    ('CN', 1.0),  -- Comoros
    ('CO', 1.0),  -- Colombia
    ('CQ', 1.0),  -- Northern Mariana Islands
    ('CS', 1.0),  -- Costa Rica
    ('CT', 1.0),  -- Central African Republic
    ('CU', 1.0),  -- Cuba
    ('CV', 1.0),  -- Cape Verde
    ('CW', 1.0),  -- Cook Islands
    ('CY', 1.0),  -- Cyprus
    ('DA', 1.0),  -- Denmark
    ('DJ', 1.0),  -- Djibouti
    ('DO', 1.0),  -- Dominica
    ('DR', 1.0),  -- Dominican Republic
    ('EC', 1.0),  -- Ecuador
    ('EG', 1.0),  -- Egypt
    ('EI', 1.0),  -- Ireland
    ('EK', 1.0),  -- Equatorial Guinea
    ('EN', 1.0),  -- Estonia
    ('ER', 1.0),  -- Eritrea
    ('ES', 1.0),  -- El Salvador
    ('ET', 1.0),  -- Ethiopia
    ('EZ', 1.0),  -- Czech Republic
    ('FG', 1.0),  -- French Guiana
    ('FI', 1.0),  -- Finland
    ('FJ', 1.0),  -- Fiji
    ('FK', 1.0),  -- Falkland Islands
    ('FM', 1.0),  -- Federated States of Micronesia
    ('FO', 1.0),  -- Faroe Islands
    ('FP', 1.0),  -- French Polynesia
    ('FR', 1.0),  -- France
    ('GA', 1.0),  -- Gambia
    ('GB', 1.0),  -- Gabon
    ('GG', 1.0),  -- Georgia
    ('GH', 1.0),  -- Ghana
    ('GI', 1.0),  -- Gibraltar
    ('GJ', 1.0),  -- Grenada
    ('GK', 1.0),  -- Guernsey
    ('GL', 1.0),  -- Greenland
    ('GM', 1.0),  -- Germany
    ('GP', 1.0),  -- Guadeloupe
    ('GQ', 1.0),  -- Guam
    ('GR', 1.0),  -- Greece
    ('GT', 1.0),  -- Guatemala
    ('GV', 1.0),  -- Guinea
    ('GY', 1.0),  -- Guyana
    ('GZ', 1.0),  -- Gaza Strip
    ('HA', 1.0),  -- Haiti
    ('HK', 1.0),  -- Hong Kong
    ('HO', 1.0),  -- Honduras
    ('HR', 1.0),  -- Croatia
    ('HU', 1.0),  -- Hungary
    ('IC', 1.0),  -- Iceland
    ('ID', 1.0),  -- Indonesia
    ('IM', 1.0),  -- Isle of Man
    ('IN', 1.0),  -- India
    ('IO', 1.0),  -- British Indian Ocean Territory
    ('IR', 1.0),  -- Iran
    ('IS', 1.0),  -- Israel
    ('IT', 1.0),  -- Italy
    ('IV', 1.0),  -- Cote d'Ivoire
    ('IZ', 1.0),  -- Iraq
    ('JA', 1.0),  -- Japan
    ('JE', 1.0),  -- Jersey
    ('JM', 1.0),  -- Jamaica
    ('JO', 1.0),  -- Jordan
    ('KE', 1.0),  -- Kenya
    ('KG', 1.0),  -- Kyrgyzstan
    ('KN', 1.0),  -- North Korea
    ('KR', 1.0),  -- Kiribati
    ('KS', 1.0),  -- South Korea
    ('KT', 1.0),  -- Christmas Island
    ('KU', 1.0),  -- Kuwait
    ('KV', 1.0),  -- Kosovo
    ('KZ', 1.0),  -- Kazakhstan
    ('LA', 1.0),  -- Laos
    ('LE', 1.0),  -- Lebanon
    ('LG', 1.0),  -- Latvia
    ('LH', 1.0),  -- Lithuania
    ('LI', 1.0),  -- Liberia
    ('LO', 1.0),  -- Slovakia
    ('LS', 1.0),  -- Liechtenstein
    ('LT', 1.0),  -- Lesotho
    ('LU', 1.0),  -- Luxembourg
    ('LY', 1.0),  -- Libya
    ('MA', 1.0),  -- Madagascar
    ('MB', 1.0),  -- Martinique
    ('MC', 1.0),  -- Macau
    ('MD', 1.0),  -- Moldova
    ('MF', 1.0),  -- Mayotte
    ('MG', 1.0),  -- Mongolia
    ('MH', 1.0),  -- Montserrat
    ('MI', 1.0),  -- Malawi
    ('MJ', 1.0),  -- Montenegro
    ('MK', 1.0),  -- North Macedonia
    ('ML', 1.0),  -- Mali
    ('MN', 1.0),  -- Monaco
    ('MO', 1.0),  -- Morocco
    ('MP', 1.0),  -- Mauritius
    ('MR', 1.0),  -- Mauritania
    ('MT', 1.0),  -- Malta
    ('MU', 1.0),  -- Oman
    ('MV', 1.0),  -- Maldives
    ('MX', 1.0),  -- Mexico
    ('MY', 1.0),  -- Malaysia
    ('MZ', 1.0),  -- Mozambique
    ('NC', 1.0),  -- New Caledonia
    ('NE', 1.0),  -- Niue
    ('NF', 1.0),  -- Norfolk Island
    ('NG', 1.0),  -- Niger
    ('NH', 1.0),  -- Vanuatu
    ('NI', 1.0),  -- Nigeria
    ('NL', 1.0),  -- Netherlands
    ('NO', 1.0),  -- Norway
    ('NP', 1.0),  -- Nepal
    ('NR', 1.0),  -- Nauru
    ('NS', 1.0),  -- Suriname
    ('NU', 1.0),  -- Nicaragua
    ('NZ', 1.0),  -- New Zealand
    ('OD', 1.0),  -- South Sudan
    ('PA', 1.0),  -- Paraguay
    ('PC', 1.0),  -- Pitcairn Islands
    ('PE', 1.0),  -- Peru
    ('PK', 1.0),  -- Pakistan
    ('PL', 1.0),  -- Poland
    ('PM', 1.0),  -- Panama
    ('PO', 1.0),  -- Portugal
    ('PP', 1.0),  -- Papua New Guinea
    ('PS', 1.0),  -- Palau
    ('PU', 1.0),  -- Guinea-Bissau
    ('QA', 1.0),  -- Qatar
    ('RE', 1.0),  -- Reunion
    ('RI', 1.0),  -- Serbia
    ('RM', 1.0),  -- Marshall Islands
    ('RN', 1.0),  -- Saint Martin
    ('RO', 1.0),  -- Romania
    ('RP', 1.0),  -- Philippines
    ('RQ', 1.0),  -- Puerto Rico
    ('RS', 1.0),  -- Russia
    ('RW', 1.0),  -- Rwanda
    ('SA', 1.0),  -- Saudi Arabia
    ('SB', 1.0),  -- Saint Pierre and Miquelon
    ('SC', 1.0),  -- Saint Kitts and Nevis
    ('SE', 1.0),  -- Seychelles
    ('SF', 1.0),  -- South Africa
    ('SG', 1.0),  -- Senegal
    ('SH', 1.0),  -- Saint Helena
    ('SI', 1.0),  -- Slovenia
    ('SL', 1.0),  -- Sierra Leone
    ('SM', 1.0),  -- San Marino
    ('SN', 1.0),  -- Singapore
    ('SO', 1.0),  -- Somalia
    ('SP', 1.0),  -- Spain
    ('ST', 1.0),  -- Saint Lucia
    ('SU', 1.0),  -- Sudan
    ('SV', 1.0),  -- Svalbard
    ('SW', 1.0),  -- Sweden
    ('SY', 1.0),  -- Syria
    ('SZ', 1.0),  -- Switzerland
    ('TD', 1.0),  -- Trinidad and Tobago
    ('TH', 1.0),  -- Thailand
    ('TI', 1.0),  -- Tajikistan
    ('TK', 1.0),  -- Turks and Caicos Islands
    ('TL', 1.0),  -- Tokelau
    ('TN', 1.0),  -- Tonga
    ('TO', 1.0),  -- Togo
    ('TP', 1.0),  -- Sao Tome and Principe
    ('TS', 1.0),  -- Tunisia
    ('TT', 1.0),  -- Timor-Leste
    ('TU', 1.0),  -- Turkey
    ('TV', 1.0),  -- Tuvalu
    ('TW', 1.0),  -- Taiwan
    ('TX', 1.0),  -- Turkmenistan
    ('TZ', 1.0),  -- Tanzania
    ('UG', 1.0),  -- Uganda
    ('UK', 1.0),  -- United Kingdom
    ('UP', 1.0),  -- Ukraine
    ('US', 1.0),  -- United States
    ('UV', 1.0),  -- Burkina Faso
    ('UY', 1.0),  -- Uruguay
    ('UZ', 1.0),  -- Uzbekistan
    ('VC', 1.0),  -- Saint Vincent and the Grenadines
    ('VE', 1.0),  -- Venezuela
    ('VI', 1.0),  -- British Virgin Islands
    ('VM', 1.0),  -- Vietnam
    ('VQ', 1.0),  -- US Virgin Islands
    ('VT', 1.0),  -- Vatican City
    ('WA', 1.0),  -- Namibia
    ('WE', 1.0),  -- West Bank
    ('WF', 1.0),  -- Wallis and Futuna
    ('WI', 1.0),  -- Western Sahara
    ('WS', 1.0),  -- Samoa
    ('WZ', 1.0),  -- Eswatini
    ('YM', 1.0),  -- Yemen
    ('ZA', 1.0),  -- Zambia
    ('ZI', 1.0)   -- Zimbabwe
ON CONFLICT (country_code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- CURATED LEADERBOARD + DIMENSION: only events that ever reached a top-10 in any timeframe.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS top_events (
    global_event_id BIGINT PRIMARY KEY,
    -- Immutable display snapshot, copied from articles_table_15_min on entry
    -- (fact rows are pruned after 7 days, so top_events must be self-sufficient).
    date_added TIMESTAMP WITH TIME ZONE,
    goldstein_scale REAL,
    event_code VARCHAR(10),
    source_url TEXT,
    action_geo_full_name TEXT,
    action_geo_type SMALLINT,
    action_geo_country_code VARCHAR(3),
    action_geo_lat REAL,
    action_geo_long REAL,
    actor1_name TEXT,
    actor1_geo_full_name TEXT,
    actor1_country_code VARCHAR(3),
    actor2_name TEXT,
    actor2_geo_full_name TEXT,
    actor2_country_code VARCHAR(3),
    -- Set once on entry, immutable afterwards.
    time_added_to_top_events TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), -- when it got to the top 10
    best_urls_json JSONB,          -- top ~5 informative links (word-content + Confidence), set once
    ai_summary TEXT,               -- LLM summary, generated once per event
    -- Recomputed every 15 min while is_dead = false.
    avg_tone REAL,                 -- GDELT AvgTone, refreshed each tick from the event's latest fact row (drifts)
    articles_1h INTEGER NOT NULL DEFAULT 0,
    articles_1d INTEGER NOT NULL DEFAULT 0,
    articles_1w INTEGER NOT NULL DEFAULT 0,
    relevance_1h REAL,
    relevance_1d REAL,
    relevance_1w REAL,
    -- Tombstone: true when time_added_to_top_events > 7 days ago AND all article
    -- windows are 0. Dead rows are kept (history) but no longer recomputed each tick.
    is_dead BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_top_relevance_1h ON top_events (relevance_1h DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_top_relevance_1d ON top_events (relevance_1d DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_top_relevance_1w ON top_events (relevance_1w DESC NULLS LAST);