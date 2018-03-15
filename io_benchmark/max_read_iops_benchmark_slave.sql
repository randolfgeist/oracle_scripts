--------------------------------------------------------------------------------
--
-- File name:   max_read_iops_benchmark_slave.sql
--
-- Version:     1.01 (March 2018)
--
--              Tested with client version SQL*Plus 11.2
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Perform physical single block read I/O mostly
--              This is the slave script that gets started by "max_read_iops_benchmark_harness.sql" as many times as requested
--
--              Parameters: The "instance" of the slave, the testtype ("ASYNC" which means asynchronous I/O ("db file parallel read" / "cell list of blocks physical read"), other valid options: "SYNC" which means synchronous I/O ("db file sequential read" / "cell single block physical read")) and the time to execute in seconds
--
-- Prereq:      Objects created by "max_read_iops_benchmark_harness.sql"
--
--------------------------------------------------------------------------------

set linesize 200 echo on timing on trimspool on tab off define "&" verify on

define tabname = &1

define thread_id = &1

define testtype = &2

define wait_time = "&3 + 10"

col sync_or_async    new_value sync_or_async noprint

select case when '&testtype' = 'ASYNC' then '--' else '' end as sync_or_async from dual;

exec dbms_application_info.set_action('SQLPSB&2')

declare
  n number;
  start_time date;
begin
  start_time := sysdate;
  loop
    select /*+
              leading(t_o)
              use_nl(t_i)
              index(t_o)
              index(t_i)
&sync_or_async              opt_param('_nlj_batching_enabled', 0)
&sync_or_async              no_nlj_prefetch(t_i)
          */
          sum(t_i.n)
          into n
    from
          t_o
        , t_i&tabname t_i
    where
          t_o.id_fk = t_i.id;
    -- insert into timings(testtype, thread_id, ts) values ('&testtype', &thread_id, systimestamp);
    -- commit;
    exit when (sysdate - start_time) * 86400 >= &wait_time;
  end loop;
end;
/

undefine tabname
undefine thread_id
undefine testtype
undefine wait_time
undefine sync_or_async

exit
