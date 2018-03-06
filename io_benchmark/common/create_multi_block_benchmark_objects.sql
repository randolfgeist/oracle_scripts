-- Create benchmark objects
declare
  procedure exec_ignore_fail(p_sql in varchar2)
  as
  begin
    execute immediate p_sql;
  exception
  when others then
    null;
  end;
begin
  for i in 1..&iter loop
    exec_ignore_fail('drop table t_i' || i);

    exec_ignore_fail('purge table t_i' || i);

    execute immediate '
create table t_i' || i || q'! (id not null, n, filler) parallel &px_degree nologging
pctfree 99 pctused 1 &tbs
as
with
generator1 as
(
  select /*+
              cardinality(1e4)
              materialize
          */
          rownum as id
        , rpad('x', 100) as filler
  from
          dual
  connect by
          level <= 1e4
),
generator2 as
(
  select /*+
              cardinality(1e4)
              materialize
          */
          rownum as id
        , rpad('x', 100) as filler
  from
          dual
  connect by
          level <= 1e4
),
source as
(
  select /*+ no_merge opt_param('_optimizer_filter_pushdown', 'false') */
        id
  from   (
            select /*+ leading(b a) use_merge_cartesian(b a) */
                    (a.id - 1) * 1e4 + b.id as id
            from
                    generator1 a
                  , generator2 b
        )
)
select cast(!' || case when '&px_degree' = '1' then 'rownum' else 'id' end || ' as integer) as id,
cast(' || case when '&px_degree' = '1' then 'rownum' else 'id' end || q'! as number) as n,
cast(rpad('x', 200) as varchar2(200)) as filler
from source
where !' || case when '&px_degree' = '1' then 'rownum' else 'id' end || ' <= &tab_size
';
    execute immediate 'begin dbms_stats.gather_table_stats(null, ''t_i' || i || '''); end;';

    execute immediate 'alter table t_i' || i || ' noparallel';
  end loop;
end;
/
