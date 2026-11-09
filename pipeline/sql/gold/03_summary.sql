-- Gold: one row of headline numbers, plus how much data each layer holds.
create or replace table gold.summary as
select
    (select count(*) from bronze.raw_events)                                     as bronze_lines,
    (select count(*) from silver.events)                                         as silver_events,
    (select count(*) from silver.quarantine)                                     as quarantined_lines,
    round((select count(*) from silver.quarantine)::double
          / nullif((select count(*) from bronze.raw_events), 0), 4)              as quarantine_rate,
    (select count(distinct session_id) from silver.events)                       as sessions,
    count(*)                                                                     as rounds,
    count(*) filter (where completed)                                            as completed_rounds,
    round(count(*) filter (where completed)::double
          / nullif(count(*) filter (where has_round_end), 0), 4)                 as completion_rate,
    sum(attempts)                                                                as attempts,
    sum(death_events)                                                            as deaths,
    round(sum(death_events)::double / nullif(sum(attempts), 0), 4)               as death_rate,
    round(avg(duration_s) filter (where completed), 3)                           as avg_duration_completed_s,
    round(median(duration_s) filter (where completed), 3)                        as median_duration_completed_s,
    min(day)                                                                     as first_day,
    max(day)                                                                     as last_day
from silver.rounds;
