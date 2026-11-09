-- Silver, step 1: parse each bronze line into typed columns (nothing is rejected yet).
-- A line that is not valid JSON has no document (doc IS NULL) and leaves every column NULL, because the JSON
-- functions raise errors on broken text. A value of the wrong type also becomes NULL.
create schema if not exists silver;

create or replace table silver.stg_events as
with parsed as (
    select source_file, line_number, raw_line, try_cast(raw_line as json) as doc
    from bronze.raw_events
)
select
    source_file,
    line_number,
    raw_line,
    coalesce(json_type(doc) = 'OBJECT', false) as is_object,
    json_extract_string(doc, '$.timestamp')                                        as ts_text,
    json_extract_string(doc, '$.evento')                                           as evento,
    json_extract_string(doc, '$.session_id')                                       as session_id,
    json_extract_string(doc, '$.round_id')                                         as round_id,
    try_cast(json_extract_string(doc, '$.schema_version') as integer)              as schema_version,
    json_extract(doc, '$.valor')::varchar                                          as valor_text,
    try_cast(json_extract_string(doc, '$.valor.t') as double)                      as t,
    try_cast(json_extract_string(doc, '$.valor.x') as double)                      as x,
    try_cast(json_extract_string(doc, '$.valor.y') as double)                      as y,
    try_cast(json_extract_string(doc, '$.valor.dt') as double)                     as dt,
    try_cast(json_extract_string(doc, '$.valor.vy') as double)                     as vy,
    try_cast(json_extract_string(doc, '$.valor.coin_id') as integer)               as coin_id,
    json_extract_string(doc, '$.valor.cause')                                      as cause,
    try_cast(json_extract_string(doc, '$.valor.level_seed') as bigint)             as level_seed,
    try_cast(json_extract_string(doc, '$.valor.generator_version') as integer)     as generator_version,
    try_cast(json_extract_string(doc, '$.valor.completed') as boolean)             as completed,
    try_cast(json_extract_string(doc, '$.valor.coins_collected') as integer)       as coins_collected,
    try_cast(json_extract_string(doc, '$.valor.coins_total') as integer)           as coins_total,
    try_cast(json_extract_string(doc, '$.valor.deaths') as integer)                as deaths,
    try_cast(json_extract_string(doc, '$.valor.jumps') as integer)                 as jumps,
    try_cast(json_extract_string(doc, '$.valor.position_samples') as integer)      as position_samples,
    try_cast(json_extract_string(doc, '$.valor.duration_s') as double)             as duration_s
from parsed;
