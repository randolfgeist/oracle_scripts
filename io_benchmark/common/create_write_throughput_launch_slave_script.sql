-- Determine what to use to spawn new processes, START on Windows and NOHUP on Unix
column os new_value os noprint

select
       coalesce('&os_name', upper(rtrim(replace(substr(banner, 1, instr(banner, ':') - 1), 'TNS for ', '')))) as os
from
       v$version
where
       banner like 'TNS for %';

store set .settings replace

-- Create a script to launch as many slaves as requested
set echo off heading off feedback off long 10000000 longchunksize 1000000 trimspool on newpage none pagesize 0 termout off verify off tab off timing off linesize 200 define "$"

spool launch_$slave_name._slave.sql

select
        case
        when instr('$os', 'WINDOWS') > 0
        then 'host start sqlplus $username/$pwd.$connect_string @$slave_name._slave ' || rownum || ' $testtype $wait_time $px_degree "$tbs" $tab_size'
        else 'host nohup sqlplus $username/$pwd.$connect_string @$slave_name._slave ' || rownum || ' $testtype $wait_time $px_degree "$tbs" $tab_size 2>&1 &'
        end
        as task
from
        dual
connect by
        level <= $iter;

spool off

@.settings

