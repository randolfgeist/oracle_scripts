--------------------------------------------------------------------------------
--
-- File name:   max_write_iops_benchmark_slave.sql
--
-- Version:     1.0 (January 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Perform physical read and write I/O mostly
--              This is the slave script that gets started by "max_write_iops_benchmark_harness.sql" as many times as requested
--
--              Parameters: The "instance" of the slave, the testtype (currently unused) and the time to execute in seconds
--
-- Prereq:      Objects created by "max_write_iops_benchmark_harness.sql"
--
--------------------------------------------------------------------------------

set linesize 200 echo on timing on trimspool on tab off define "&" verify on

define tabname = &1

define thread_id = &1

define testtype = &2

define wait_time = "&3 + 10"

exec dbms_application_info.set_action('SQLPWIO&2')

declare
  n number;
  start_time date;
  type nt is table of number;
  fks nt;
begin
  select /*+
              index(t_o)
           */
          id_fk
    bulk collect
    into fks
    from
          t_o;
  start_time := sysdate;
  loop
    n := 0;
    for rec in fks.first..fks.last loop
      update t_i&tabname t_i
      -- 12.2.0.1 optimizes the former n = id.fk
      -- subsequent changes to the same value
      -- do not cause a "db block change"
      -- and as a consequence less undo / redo generated
      set n = n + decode(mod(n, 2), 0, -1, 1)
      where id = fks(rec);
      n := n + 1;
      if mod(n, 1000) = 0 then
        exit when (sysdate - start_time) * 86400 >= &wait_time;
      end if;
      if n > 100000 then
        commit write batch nowait;
        n := 0;
      end if;
    end loop;
    -- insert into timings(testtype, thread_id, ts) values ('&testtype', &thread_id, systimestamp);
    commit write batch nowait;
    exit when (sysdate - start_time) * 86400 >= &wait_time;
  end loop;
end;
/

undefine tabname
undefine thread_id
undefine testtype
undefine wait_time
