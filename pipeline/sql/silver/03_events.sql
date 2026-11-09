-- Silver, step 3: the clean events (one conformed shape for schema versions 2, 3 and 4) and the quarantine.
--   * version 2 had a single fixed level, so its round_start has no level_seed: it is level 0.
--   * generator_version only exists from schema 4; versions 2 and 3 correspond to generator version 1.

create or replace table silver.events as
select
    source_file,
    line_number,
    ts,
    cast(ts as date) as day,
    evento,
    session_id,
    round_id,
    schema_version,
    t, x, y, dt, vy, coin_id, cause,
    case when evento = 'round_start' then coalesce(level_seed, 0) end as level_seed,
    case when evento = 'round_start' then coalesce(generator_version, 1) end as generator_version,
    completed, coins_collected, coins_total, deaths, jumps, position_samples, duration_s
from silver.stg_classified
where reject_reason is null;

-- Every rejected line, with why, and where it came from in bronze.
create or replace table silver.quarantine as
select source_file, line_number, reject_reason, raw_line
from silver.stg_classified
where reject_reason is not null;
