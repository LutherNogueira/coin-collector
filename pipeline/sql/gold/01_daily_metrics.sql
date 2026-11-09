-- Gold: metrics per day (UTC), from the silver rounds.
--   completion_rate = completed rounds / rounds that ended        (a round with no round_end is "unfinished")
--   death_rate      = deaths / attempts                           (an attempt = one start of the level)
--   durations are for completed rounds only; the median sits next to the mean because a few long rounds skew it
create schema if not exists gold;

create or replace table gold.daily_metrics as
with sessions as (
    select day, count(distinct session_id) as sessions
    from silver.events
    where evento = 'session_start'
    group by day
)
select
    r.day,
    coalesce(max(s.sessions), 0)                                                              as sessions,
    count(*)                                                                                  as rounds,
    count(*) filter (where r.completed)                                                       as completed_rounds,
    count(*) filter (where r.has_round_end and not r.completed)                               as abandoned_rounds,
    count(*) filter (where not r.has_round_end)                                               as unfinished_rounds,
    round(count(*) filter (where r.completed)::double
          / nullif(count(*) filter (where r.has_round_end), 0), 4)                            as completion_rate,
    sum(r.attempts)                                                                           as attempts,
    sum(r.death_events)                                                                       as deaths,
    round(sum(r.death_events)::double / nullif(sum(r.attempts), 0), 4)                        as death_rate,
    round(avg(r.duration_s) filter (where r.completed), 3)                                    as avg_duration_completed_s,
    round(median(r.duration_s) filter (where r.completed), 3)                                 as median_duration_completed_s
from silver.rounds r
left join sessions s using (day)
group by r.day
order by r.day;
