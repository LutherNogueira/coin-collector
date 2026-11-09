-- Silver, step 2: decide for every line whether it is clean or why it is rejected.
-- The first rule that fails wins, so each rejected line has exactly one reason:
--   invalid_json, missing_field, invalid_timestamp, timestamp_out_of_range, unsupported_schema_version,
--   unknown_event, value_out_of_range, duplicate
-- Supported schema versions are 2, 3 and 4 (version 1 was the arena game, a different data model).

create or replace table silver.stg_classified as
with base as (
    select
        *,
        coalesce(regexp_matches(ts_text, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'), false) as ts_format_ok,
        try_cast(replace(ts_text, 'Z', '') as timestamp) as ts
    from silver.stg_events
),
first_pass as (
    select
        *,
        case
            when not is_object then 'invalid_json'
            when session_id is null or evento is null or ts_text is null or schema_version is null then 'missing_field'
            when not ts_format_ok or ts is null then 'invalid_timestamp'
            when ts < timestamp '2026-01-01' or ts > now()::timestamp + interval 1 day then 'timestamp_out_of_range'
            when schema_version not in (2, 3, 4) then 'unsupported_schema_version'
            when evento not in ('session_start', 'session_end', 'round_start', 'coin_spawn', 'coin_collect',
                                'player_position', 'player_jump', 'player_land', 'player_death', 'player_respawn',
                                'round_end') then 'unknown_event'
            when evento not in ('session_start', 'session_end') and round_id is null then 'missing_field'
            when case evento
                    when 'round_start' then t is null
                        or (schema_version >= 3 and level_seed is null)
                        or (schema_version >= 4 and generator_version is null)
                    when 'coin_spawn' then t is null or coin_id is null or x is null or y is null
                    when 'coin_collect' then t is null or coin_id is null or x is null or y is null or dt is null
                    when 'player_position' then t is null or x is null or y is null
                    when 'player_jump' then t is null or x is null or y is null
                    when 'player_respawn' then t is null or x is null or y is null
                    when 'player_land' then t is null or x is null or y is null or vy is null
                    when 'player_death' then t is null or x is null or y is null or cause is null
                    when 'round_end' then t is null or completed is null or coins_collected is null or coins_total is null
                        or deaths is null or jumps is null or position_samples is null or duration_s is null
                    else false
                 end then 'missing_field'
            when coalesce(
                     x < 0 or x > 800
                     or y < -200 or y > 800
                     or t < 0 or t > 86400
                     or dt < 0 or vy < 0 or coin_id < 0
                     or cause not in ('trap', 'pit')
                     or level_seed < 0 or level_seed > 2147483647
                     or coins_collected < 0 or coins_total < 0 or deaths < 0 or jumps < 0
                     or position_samples < 0 or duration_s < 0,
                     false) then 'value_out_of_range'
        end as reason
    from base
),
-- Duplicates are numbered among the lines that passed every rule above. Numbering all lines would let a corrupted
-- copy that comes first make the genuine line look like the repeat, and the genuine line would be thrown away.
occurrences as (
    select
        source_file,
        line_number,
        row_number() over (
            partition by session_id, round_id, evento, ts_text, valor_text
            order by source_file, line_number
        ) as occurrence
    from first_pass
    where reason is null
)
select
    f.* exclude (reason),
    coalesce(f.reason, case when o.occurrence > 1 then 'duplicate' end) as reject_reason
from first_pass f
left join occurrences o using (source_file, line_number);
