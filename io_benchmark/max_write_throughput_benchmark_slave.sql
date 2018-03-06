--------------------------------------------------------------------------------
--
-- File name:   max_write_throughput_benchmark_slave.sql
--
-- Version:     1.0 (January 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Perform physical direct write I/O mostly
--              This is the slave script that gets started by "max_write_throughput_benchmark_harness.sql" as many times as requested
--
--              Parameters: The "instance" of the slave, the testtype (currently unused), the time to execute in seconds, the PX degree to use for the CTAS operation, the tablespace definition and the number of blocks / rows to create
--
-- Prereq:      Objects created by "max_write_throughput_benchmark_harness.sql"
--
--------------------------------------------------------------------------------

set linesize 200 echo on timing on trimspool on tab off define "&" verify on

define tabname = &1

define thread_id = &1

define testtype = &2

define wait_time = "&3 + 10"

define px_degree = &4

define tbs = "&5"

define tab_size = &6

exec dbms_application_info.set_action('SQLPWMB&2')

declare
  n number;
  start_time date;
  procedure exec_ignore_fail(p_sql in varchar2)
  as
  begin
    execute immediate p_sql;
  exception
  when others then
    null;
  end;
begin
  start_time := sysdate;
  loop
    exec_ignore_fail('drop table t_i&tabname');

    exec_ignore_fail('purge table t_i&tabname');

    execute immediate '
create /*+ NO_GATHER_OPTIMIZER_STATISTICS */ table t_i&tabname' || q'! (id not null, n, filler) parallel &px_degree nologging
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
    exit when (sysdate - start_time) * 86400 >= &wait_time;
  end loop;
end;
/


undefine tabname
undefine thread_id
undefine testtype
undefine wait_time
undefine px_degree
undefine tbs
undefine tab_size