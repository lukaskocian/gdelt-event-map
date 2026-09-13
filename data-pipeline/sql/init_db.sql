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
    goldstein_scale REAL NOT NULL,
    source_url TEXT,
    event_code VARCHAR(10),
    action_geo_full_name TEXT,
    action_geo_type SMALLINT,
    action_geo_country_code VARCHAR(3) NOT NULL,
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
-- CURATED LEADERBOARD + DIMENSION: only events that ever reached a top-10 in any timeframe.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS top_events (
    global_event_id BIGINT PRIMARY KEY,
    -- Immutable display snapshot, copied from articles_table_15_min on entry
    date_added TIMESTAMP WITH TIME ZONE,
    goldstein_scale REAL NOT NULL,
    event_code VARCHAR(10),
    source_url TEXT,
    action_geo_full_name TEXT,
    action_geo_type SMALLINT,
    action_geo_country_code VARCHAR(3) NOT NULL,
    action_geo_lat REAL,
    action_geo_long REAL,
    actor1_name TEXT,
    actor1_geo_full_name TEXT,
    actor1_country_code VARCHAR(3),
    actor2_name TEXT,
    actor2_geo_full_name TEXT,
    actor2_country_code VARCHAR(3),
    -- Set once on entry, immutable afterwards
    time_added_to_top_events TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    best_urls_json JSONB,
    ai_summary TEXT,
    ai_evidence_quality SMALLINT,
    -- Recomputed every 15 min by refresh_top_events.sql. Each tick every row is first
    avg_tone REAL,
    articles_1h INTEGER NOT NULL DEFAULT 0,
    articles_1d INTEGER NOT NULL DEFAULT 0,
    articles_1w INTEGER NOT NULL DEFAULT 0,
    relevance_1h REAL NOT NULL,
    relevance_1d REAL NOT NULL,
    relevance_1w REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_top_relevance_1h ON top_events (relevance_1h DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_top_relevance_1d ON top_events (relevance_1d DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_top_relevance_1w ON top_events (relevance_1w DESC NULLS LAST);

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

CREATE TABLE IF NOT EXISTS event_cameo_codes (
    event_code VARCHAR(10) PRIMARY KEY,
    event_description VARCHAR(100)
);

INSERT INTO event_cameo_codes (event_code, event_description) VALUES
('01', 'MAKE PUBLIC STATEMENT'),
('010', 'Make statement, not specified below'),
('011', 'Decline comment'),
('012', 'Make pessimistic comment'),
('013', 'Make optimistic comment'),
('014', 'Consider policy option'),
('015', 'Acknowledge or claim responsibility'),
('016', 'Deny responsibility'),
('017', 'Engage in symbolic act'),
('018', 'Make empathetic comment'),
('019', 'Express accord'),
('02', 'APPEAL'),
('020', 'Appeal, not specified below'),
('021', 'Appeal for material cooperation, not specified below'),
('0211', 'Appeal for economic cooperation'),
('0212', 'Appeal for military cooperation'),
('0213', 'Appeal for judicial cooperation'),
('0214', 'Appeal for intelligence'),
('022', 'Appeal for diplomatic cooperation, such as policy support'),
('023', 'Appeal for aid, not specified below'),
('0231', 'Appeal for economic aid'),
('0232', 'Appeal for military aid'),
('0233', 'Appeal for humanitarian aid'),
('0234', 'Appeal for military protection or peacekeeping'),
('024', 'Appeal for political reform, not specified below'),
('0241', 'Appeal for change in leadership'),
('0242', 'Appeal for policy change'),
('0243', 'Appeal for rights'),
('0244', 'Appeal for change in institutions, regime'),
('025', 'Appeal to yield'),
('0251', 'Appeal for easing of administrative sanctions'),
('0252', 'Appeal for easing of popular dissent'),
('0253', 'Appeal for release of persons or property'),
('0254', 'Appeal for easing of economic sanctions, boycott, or embargo'),
('0255', 'Appeal for target to allow international involvement'),
('0256', 'Appeal for de-escalation of military engagement'),
('026', 'Appeal to others to meet or negotiate'),
('027', 'Appeal to others to settle dispute'),
('028', 'Appeal to others to engage in or accept mediation'),
('03', 'EXPRESS INTENT TO COOPERATE'),
('030', 'Express intent to cooperate, not specified below'),
('031', 'Express intent to engage in material cooperation, not specified below'),
('0311', 'Express intent to cooperate economically'),
('0312', 'Express intent to cooperate militarily'),
('0313', 'Express intent to cooperate on judicial matters'),
('0314', 'Express intent to cooperate on intelligence'),
('032', 'Express intent to provide diplomatic cooperation such as policy support'),
('033', 'Express intent to provide material aid, not specified below'),
('0331', 'Express intent to provide economic aid'),
('0332', 'Express intent to provide military aid'),
('0333', 'Express intent to provide humanitarian aid'),
('0334', 'Express intent to provide military protection or peacekeeping'),
('034', 'Express intent to institute political reform, not specified below'),
('0341', 'Express intent to change leadership'),
('0342', 'Express intent to change policy'),
('0343', 'Express intent to provide rights'),
('0344', 'Express intent to change institutions, regime'),
('035', 'Express intent to yield, not specified below'),
('0351', 'Express intent to ease administrative sanctions'),
('0352', 'Express intent to ease popular dissent'),
('0353', 'Express intent to release persons or property'),
('0354', 'Express intent to ease economic sanctions, boycott, or embargo'),
('0355', 'Express intent allow international involvement'),
('0356', 'Express intent to de-escalate military engagement'),
('036', 'Express intent to meet or negotiate'),
('037', 'Express intent to settle dispute'),
('038', 'Express intent to accept mediation'),
('039', 'Express intent to mediate'),
('04', 'CONSULT'),
('040', 'Consult, not specified below'),
('041', 'Discuss by telephone'),
('042', 'Make a visit'),
('043', 'Host a visit'),
('044', 'Meet at a third location'),
('045', 'Mediate'),
('046', 'Engage in negotiation'),
('05', 'ENGAGE IN DIPLOMATIC COOPERATION'),
('050', 'Engage in diplomatic cooperation, not specified below'),
('051', 'Praise or endorse'),
('052', 'Defend verbally'),
('053', 'Rally support on behalf of'),
('054', 'Grant diplomatic recognition'),
('055', 'Apologize'),
('056', 'Forgive'),
('057', 'Sign formal agreement'),
('06', 'ENGAGE IN MATERIAL COOPERATION'),
('060', 'Engage in material cooperation, not specified below'),
('061', 'Cooperate economically'),
('062', 'Cooperate militarily'),
('063', 'Engage in judicial cooperation'),
('064', 'Share intelligence or information'),
('07', 'PROVIDE AID'),
('070', 'Provide aid, not specified below'),
('071', 'Provide economic aid'),
('072', 'Provide military aid'),
('073', 'Provide humanitarian aid'),
('074', 'Provide military protection or peacekeeping'),
('075', 'Grant asylum'),
('08', 'YIELD'),
('080', 'Yield, not specified below'),
('081', 'Ease administrative sanctions, not specified below'),
('0811', 'Ease restrictions on political freedoms'),
('0812', 'Ease ban on political parties or politicians'),
('0813', 'Ease curfew'),
('0814', 'Ease state of emergency or martial law'),
('082', 'Ease political dissent'),
('083', 'Accede to requests or demands for political reform not specified below'),
('0831', 'Accede to demands for change in leadership'),
('0832', 'Accede to demands for change in policy'),
('0833', 'Accede to demands for rights'),
('0834', 'Accede to demands for change in institutions, regime'),
('084', 'Return, release, not specified below'),
('0841', 'Return, release person(s)'),
('0842', 'Return, release property'),
('085', 'Ease economic sanctions, boycott, embargo'),
('086', 'Allow international involvement not specified below'),
('0861', 'Receive deployment of peacekeepers'),
('0862', 'Receive inspectors'),
('0863', 'Allow delivery of humanitarian aid'),
('087', 'De-escalate military engagement'),
('0871', 'Declare truce, ceasefire'),
('0872', 'Ease military blockade'),
('0873', 'Demobilize armed forces'),
('0874', 'Retreat or surrender militarily'),
('09', 'INVESTIGATE'),
('090', 'Investigate, not specified below'),
('091', 'Investigate crime, corruption'),
('092', 'Investigate human rights abuses'),
('093', 'Investigate military action'),
('094', 'Investigate war crimes'),
('10', 'DEMAND'),
('100', 'Demand, not specified below'),
('101', 'Demand information, investigation'),
('1011', 'Demand economic cooperation'),
('1012', 'Demand military cooperation'),
('1013', 'Demand judicial cooperation'),
('1014', 'Demand intelligence cooperation'),
('102', 'Demand policy support'),
('103', 'Demand aid, protection, or peacekeeping'),
('1031', 'Demand economic aid'),
('1032', 'Demand military aid'),
('1033', 'Demand humanitarian aid'),
('1034', 'Demand military protection or peacekeeping'),
('104', 'Demand political reform, not specified below'),
('1041', 'Demand change in leadership'),
('1042', 'Demand policy change'),
('1043', 'Demand rights'),
('1044', 'Demand change in institutions, regime'),
('105', 'Demand mediation'),
('1051', 'Demand easing of administrative sanctions'),
('1052', 'Demand easing of political dissent'),
('1053', 'Demand release of persons or property'),
('1054', 'Demand easing of economic sanctions, boycott, or embargo'),
('1055', 'Demand that target allows international involvement (non-mediation)'),
('1056', 'Demand de-escalation of military engagement'),
('106', 'Demand withdrawal'),
('107', 'Demand ceasefire'),
('108', 'Demand meeting, negotiation'),
('11', 'DISAPPROVE'),
('110', 'Disapprove, not specified below'),
('111', 'Criticize or denounce'),
('112', 'Accuse, not specified below'),
('1121', 'Accuse of crime, corruption'),
('1122', 'Accuse of human rights abuses'),
('1123', 'Accuse of aggression'),
('1124', 'Accuse of war crimes'),
('1125', 'Accuse of espionage, treason'),
('113', 'Rally opposition against'),
('114', 'Complain officially'),
('115', 'Bring lawsuit against'),
('116', 'Find guilty or liable (legally)'),
('12', 'REJECT'),
('120', 'Reject, not specified below'),
('121', 'Reject material cooperation'),
('1211', 'Reject economic cooperation'),
('1212', 'Reject military cooperation'),
('122', 'Reject request or demand for material aid, not specified below'),
('1221', 'Reject request for economic aid'),
('1222', 'Reject request for military aid'),
('1223', 'Reject request for humanitarian aid'),
('1224', 'Reject request for military protection or peacekeeping'),
('123', 'Reject request or demand for political reform, not specified below'),
('1231', 'Reject request for change in leadership'),
('1232', 'Reject request for policy change'),
('1233', 'Reject request for rights'),
('1234', 'Reject request for change in institutions, regime'),
('124', 'Refuse to yield, not specified below'),
('1241', 'Refuse to ease administrative sanctions'),
('1242', 'Refuse to ease popular dissent'),
('1243', 'Refuse to release persons or property'),
('1244', 'Refuse to ease economic sanctions, boycott, or embargo'),
('1245', 'Refuse to allow international involvement (non mediation)'),
('1246', 'Refuse to de-escalate military engagement'),
('125', 'Reject proposal to meet, discuss, or negotiate'),
('126', 'Reject mediation'),
('127', 'Reject plan, agreement to settle dispute'),
('128', 'Defy norms, law'),
('129', 'Veto'),
('13', 'THREATEN'),
('130', 'Threaten, not specified below'),
('131', 'Threaten non-force, not specified below'),
('1311', 'Threaten to reduce or stop aid'),
('1312', 'Threaten to boycott, embargo, or sanction'),
('1313', 'Threaten to reduce or break relations'),
('132', 'Threaten with administrative sanctions, not specified below'),
('1321', 'Threaten to impose restrictions on political freedoms'),
('1322', 'Threaten to ban political parties or politicians'),
('1323', 'Threaten to impose curfew'),
('1324', 'Threaten to impose state of emergency or martial law'),
('133', 'Threaten political dissent, protest'),
('134', 'Threaten to halt negotiations'),
('135', 'Threaten to halt mediation'),
('136', 'Threaten to halt international involvement (non-mediation)'),
('137', 'Threaten with violent repression'),
('138', 'Threaten to use military force, not specified below'),
('1381', 'Threaten blockade'),
('1382', 'Threaten occupation'),
('1383', 'Threaten unconventional violence'),
('1384', 'Threaten conventional attack'),
('1385', 'Threaten attack with WMD'),
('139', 'Give ultimatum'),
('14', 'PROTEST'),
('140', 'Engage in political dissent, not specified below'),
('141', 'Demonstrate or rally'),
('1411', 'Demonstrate for leadership change'),
('1412', 'Demonstrate for policy change'),
('1413', 'Demonstrate for rights'),
('1414', 'Demonstrate for change in institutions, regime'),
('142', 'Conduct hunger strike, not specified below'),
('1421', 'Conduct hunger strike for leadership change'),
('1422', 'Conduct hunger strike for policy change'),
('1423', 'Conduct hunger strike for rights'),
('1424', 'Conduct hunger strike for change in institutions, regime'),
('143', 'Conduct strike or boycott, not specified below'),
('1431', 'Conduct strike or boycott for leadership change'),
('1432', 'Conduct strike or boycott for policy change'),
('1433', 'Conduct strike or boycott for rights'),
('1434', 'Conduct strike or boycott for change in institutions, regime'),
('144', 'Obstruct passage, block'),
('1441', 'Obstruct passage to demand leadership change'),
('1442', 'Obstruct passage to demand policy change'),
('1443', 'Obstruct passage to demand rights'),
('1444', 'Obstruct passage to demand change in institutions, regime'),
('145', 'Protest violently, riot'),
('1451', 'Engage in violent protest for leadership change'),
('1452', 'Engage in violent protest for policy change'),
('1453', 'Engage in violent protest for rights'),
('1454', 'Engage in violent protest for change in institutions, regime'),
('15', 'EXHIBIT FORCE POSTURE'),
('150', 'Demonstrate military or police power, not specified below'),
('151', 'Increase police alert status'),
('152', 'Increase military alert status'),
('153', 'Mobilize or increase police power'),
('154', 'Mobilize or increase armed forces'),
('16', 'REDUCE RELATIONS'),
('160', 'Reduce relations, not specified below'),
('161', 'Reduce or break diplomatic relations'),
('162', 'Reduce or stop aid, not specified below'),
('1621', 'Reduce or stop economic assistance'),
('1622', 'Reduce or stop military assistance'),
('1623', 'Reduce or stop humanitarian assistance'),
('163', 'Impose embargo, boycott, or sanctions'),
('164', 'Halt negotiations'),
('165', 'Halt mediation'),
('166', 'Expel or withdraw, not specified below'),
('1661', 'Expel or withdraw peacekeepers'),
('1662', 'Expel or withdraw inspectors, observers'),
('1663', 'Expel or withdraw aid agencies'),
('17', 'COERCE'),
('170', 'Coerce, not specified below'),
('171', 'Seize or damage property, not specified below'),
('1711', 'Confiscate property'),
('1712', 'Destroy property'),
('172', 'Impose administrative sanctions, not specified below'),
('1721', 'Impose restrictions on political freedoms'),
('1722', 'Ban political parties or politicians'),
('1723', 'Impose curfew'),
('1724', 'Impose state of emergency or martial law'),
('173', 'Arrest, detain, or charge with legal action'),
('174', 'Expel or deport individuals'),
('175', 'Use tactics of violent repression'),
('18', 'ASSAULT'),
('180', 'Use unconventional violence, not specified below'),
('181', 'Abduct, hijack, or take hostage'),
('182', 'Physically assault, not specified below'),
('1821', 'Sexually assault'),
('1822', 'Torture'),
('1823', 'Kill by physical assault'),
('183', 'Conduct suicide, car, or other non-military bombing, not spec below'),
('1831', 'Carry out suicide bombing'),
('1832', 'Carry out car bombing'),
('1833', 'Carry out roadside bombing'),
('184', 'Use as human shield'),
('185', 'Attempt to assassinate'),
('186', 'Assassinate'),
('19', 'FIGHT'),
('190', 'Use conventional military force, not specified below'),
('191', 'Impose blockade, restrict movement'),
('192', 'Occupy territory'),
('193', 'Fight with small arms and light weapons'),
('194', 'Fight with artillery and tanks'),
('195', 'Employ aerial weapons'),
('196', 'Violate ceasefire'),
('20', 'USE UNCONVENTIONAL MASS VIOLENCE'),
('200', 'Use unconventional mass violence, not specified below'),
('201', 'Engage in mass expulsion'),
('202', 'Engage in mass killings'),
('203', 'Engage in ethnic cleansing'),
('204', 'Use weapons of mass destruction, not specified below'),
('2041', 'Use chemical, biological, or radiological weapons'),
('2042', 'Detonate nuclear weapons');