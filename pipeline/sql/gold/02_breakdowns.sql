-- Gold: breakdowns of the deaths and the levels, and a picture of data quality.

create or replace table gold.deaths_by_cause as
select
    cause,
    count(*) as deaths,
    round(count(*)::double / sum(count(*)) over (), 4) as share
from silver.deaths
group by cause
order by deaths desc, cause;

-- A seed only reproduces its level under the same generator version, so both identify a level.
-- Seed 0 is the hand-made level, so it gathers many rounds; any other seed is usually one round.
create or replace table gold.deadliest_levels as
select
    level_seed,
    generator_version,
    case when level_seed = 0 then 'hand-made' else 'generated' end as kind,
    count(*)                                                       as rounds,
    sum(attempts)                                                  as attempts,
    sum(death_events)                                              as deaths,
    round(sum(death_events)::double / sum(attempts), 4)            as death_rate
from silver.rounds
group by level_seed, generator_version
having sum(attempts) >= 3
order by death_rate desc, deaths desc, level_seed
limit 10;

-- Which lines were rejected, and why.
create or replace table gold.data_quality as
select
    reject_reason                                                                  as reason,
    count(*)                                                                       as lines,
    round(count(*)::double / (select count(*) from bronze.raw_events), 4)          as share_of_lines
from silver.quarantine
group by reject_reason
order by lines desc, reason;
