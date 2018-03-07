-- Create benchmark objects
--
-- Note on creating larger objects than the current default:
-- If you want to create objects larger than the current limit of 1e4 * 1e4 = 100.000.000 blocks
-- you can modify the "level <= 1e4" predicate below accordingly
-- Ideally modify the "cardinality(1e4)" hint, too, so that the optimizer knows about the data volume
-- Note that there are two "generator" sources per CREATE TABLE, and in principle a cartesian join is performed
-- and filtered afterwards on ROWNUM (serial) resp. ID (px)
-- So check carefully how you want to change the number of rows per "generator" source
-- Note that there is a driving table T_O and n inner tablesd T_In per concurrent process
-- Ideally you need to do apply this change across both CREATE TABLE statements, so in total four times
--
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
  exec_ignore_fail('drop table t_o');

  exec_ignore_fail('purge table t_o');

  execute immediate q'!
create table t_o (id primary key, id_fk)
organization index &tbs
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
  select
        id
  from   (
            select /*+ leading(b a) */
                    (a.id - 1) * 1e4 + b.id as id
            from
                    generator1 a
                  , generator2 b
        )
)
select
       rownum as id
--     , case mod(rownum, 2) + 1
--       when 1
--       then mod(rownum, &tab_size * 10 / 20)
--       else &tab_size * 10 / 10 - mod(rownum, &tab_size * 10 / 20) + 1
--       end as id_fk
     , case mod(rownum, 2)
       when 1
       then mod(rownum, &tab_size) + 1
       else &tab_size - 1 - mod(rownum - 1, &tab_size) + 1
       end as id_fk
from
       source
where
       rownum <= &tab_size * 10
!';

  execute immediate 'begin dbms_stats.gather_table_stats(null, ''t_o''); end;';

  execute immediate 'alter table t_o noparallel';

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
    execute immediate 'create index t_i' || i || '_idx on t_i' || i || ' (id, filler) parallel &px_degree nologging pctfree 99 &tbs';

    execute immediate 'alter index t_i' || i || '_idx noparallel';

    execute immediate 'begin dbms_stats.gather_table_stats(null, ''t_i' || i || '''); end;';

    execute immediate 'alter table t_i' || i || ' noparallel';
  end loop;
end;
/

