--------------------------------------------------------------------------------
--
-- File name:   max_read_throughput_benchmark_slave.sql
--
-- Version:     1.03 (April 2019)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Perform physical multi block read I/O mostly
--              This is the slave script that gets started by "max_read_throughput_benchmark_harness.sql" as many times as requested
--
--              Parameters: The "instance" of the slave, the testtype ("ASYNC" which means asynchronous (bypassing buffer cache) I/O ("direct path read" / "cell smart table/index scan"), other valid options: "SYNC" which means synchronous I/O ("db file scattered read" / "cell multiblock physical read")
--
-- Prereq:      Objects created by "max_read_throughput_benchmark_harness.sql"
--
--------------------------------------------------------------------------------

set linesize 200 echo on timing on trimspool on tab off define "&" verify on

define tabname = &1

define thread_id = &1

define testtype = &2

define wait_time = "&3 + 10"

col sync_or_async    new_value sync_or_async noprint

select case when '&testtype' = 'ASYNC' then 'always' else 'never' end as sync_or_async from dual;

alter session set "_serial_direct_read" = &sync_or_async;

exec dbms_application_info.set_action('SQLPMB&2')

declare
  n number;
  start_time date;
begin
  start_time := sysdate;
  loop
    select
          sum(t_i.n)
          into n
    from
          t_i&tabname t_i
;
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
