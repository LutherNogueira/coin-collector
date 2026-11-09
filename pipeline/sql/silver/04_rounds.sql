-- Silver, step 4: business entities built from the clean events.
--   rounds: one row per round. An attempt starts the level, so attempts = 1 + respawns.
--   deaths: one row per death, with the level it happened on.

create or replace table silver.rounds as
with starts as (
    select round_id, session_id, ts as started_at, day, level_seed, generator_version, schema_version
    from silver.events
    where evento = 'round_start'
    qualify row_number() over (partition by round_id order by ts, line_number) = 1
),
ends as (
    select round_id, ts as ended_at, completed, coins_collected, coins_total, jumps, duration_s
    from silver.events
    where evento = 'round_end'
    qualify row_number() over (partition by round_id order by ts, line_number) = 1
),
respawns as (
    select round_id, count(*) as respawns from silver.events where evento = 'player_respawn' group by round_id
),
death_counts as (
    select round_id, count(*) as death_events from silver.events where evento = 'player_death' group by round_id
)
select
    s.round_id,
    s.session_id,
    s.started_at,
    s.day,
    s.level_seed,
    s.generator_version,
    s.schema_version,
    e.ended_at,
    e.round_id is not null as has_round_end,
    e.completed,
    e.coins_collected,
    e.coins_total,
    e.jumps,
    e.duration_s,
    1 + coalesce(r.respawns, 0) as attempts,
    coalesce(d.death_events, 0) as death_events
from starts s
left join ends e using (round_id)
left join respawns r using (round_id)
left join death_counts d using (round_id);

create or replace table silver.deaths as
select
    e.round_id,
    e.session_id,
    e.ts,
    e.day,
    e.cause,
    e.x,
    e.y,
    e.t,
    r.level_seed,
    r.generator_version
from silver.events e
left join silver.rounds r using (round_id)
where e.evento = 'player_death';
