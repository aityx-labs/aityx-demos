# Care centers

The hospitals, clinics and health stations HealthHub knows: 7,256 in
seven cities, from each country's official registries, in the
`care_centers` table ([Database](database.md)), served by
`GET /api/care-centers` ([API](api.md)) and pinned on [the map](map.md).

| City | Hospitals | Clinics | Health stations | Total |
|---|---|---|---|---|
| Cornudella de Montsant (ES) | 0 | 0 | 1 | 1 |
| Reus (ES) | 5 | 5 | 6 | 16 |
| Barcelona (ES) | 57 | 238 | 55 | 350 |
| Miami (US) | 9 | 30 | 34 | 73 |
| Fort Lauderdale (US) | 5 | 33 | 8 | 46 |
| Rio de Janeiro (BR) | 181 | 2,156 | 254 | 2,591 |
| São Paulo (BR) | 230 | 3,458 | 491 | 4,179 |

## Kinds

- **hospital**: inpatient hospitals of any kind (general, specialty,
  psychiatric, maternity, children's, long stay).
- **clinic**: outpatient care: specialty clinics, polyclinics, urgent
  care without beds (CUAP, UPA, pronto atendimento), day hospitals,
  ambulatory surgery and dialysis centres, outpatient mental health
  (CSMA, CSMIJ, CAS, CAPS), private clinics with several practitioners.
- **health_station**: primary care: CAP and consultori local in
  Catalonia, UBS, centro de saúde, posto de saúde and clínica da família
  in Brazil, community and county health centres and FQHC sites in
  Florida.

Pharmacies, laboratories, imaging-only centres, dentist-only practices,
single-practitioner offices, nursing homes, mobile units and
administrative units are left out. Every row keeps the source's own
type as `subtype` ("CAP (Centro de Salud)", "Hospital Geral",
"Urgent care"...).

## Sources

- **Catalonia**: the Ministry of Health's Catálogo Nacional de
  Hospitales 2025 and its 2026 catalogues of primary-care and
  out-of-hospital urgent-care centres (SIAP), the Generalitat's
  Equipaments de Catalunya, Barcelona's equipament-sanitat directory,
  and the ICGC geocoder for 21 rows without coordinates (Spanish public
  sector information, CC BY 4.0).
- **Florida**: AHCA's licensed facilities (HFRS, and Broward County's
  geocoded copy), Miami-Dade's ambulatory surgical centres, CMS's
  provider of services file, HRSA's health center sites, the Department
  of Health's county health department sites, HIFLD hospitals, and the
  Census Bureau's city limits and geocoder (public records and US
  government works).
- **Brazil**: CNES, the national registry of health establishments
  (DATASUS, September 2026), active establishments of the municipalities
  of Rio de Janeiro (330455) and São Paulo (355030) by unit type (open
  data, attribution to the Ministério da Saúde).

Each city was then checked by an independent pass: missing facilities
added from official and secondary sources, closed, duplicate or
out-of-city rows removed, and a sample spot-checked. Cornudella's one
row is its CAP (Carrer Comte de Rius 2 bis); its consultoris locals are
in the neighbouring municipalities.

## Data and seeding

The rows live in
[healthhub_api/data/care_centers.jsonl](../healthhub_api/data/care_centers.jsonl),
one JSON object a line: `name`, `kind`, `subtype`, `address`,
`postal_code`, `city`, `region`, `country` (ISO 3166-1 alpha-2), `lat`,
`lon` (WGS84, or null), `phone`, `website` (an address with an `@` is
an email, sometimes a person's, and is read as none), `ownership` (`public`,
`private` or `unknown`), `source` and `source_id`. The API ships as one
native executable, so `dart run tool/generate_care_centers.dart` (in
`healthhub_api/`) compiles the file into `lib/care_centers_seed.dart`;
a test fails when the two differ. At every start the migration makes
the table hold exactly the seed: rows inserted or updated by their key
(the source and its id for the facility, else the country, city, name
and address), in batches of 500, and rows no longer in the seed deleted,
in one transaction.

## Known limitations

- 666 rows have no coordinates (mostly CNES records), so they are in the
  database but not on the map.
- Brazil's and Barcelona's private clinics come from registries without
  a closing date; some may have closed. Reus and Cornudella have no open
  directory of private clinics, so their clinics are the public ones.
- A snapshot: nothing refreshes the data from the sources.
