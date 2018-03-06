store set .settings replace

set define "$"

-- Launch the slaves
@launch_$slave_name._slave

@.settings

column snapshot_call new_value snapshot_call

select case '&awr_statspack'
       when 'AWR'
       then 'dbms_workload_repository.create_snapshot'
       when 'STATSPACK'
       then 'perfstat.statspack.snap'
       else '0'
       end as snapshot_call
from
       dual;


-- Wait a couple of seconds so that hopefully all slaves have connected and started
exec dbms_lock.sleep(5)

column rep_start_time new_value rep_start_time noprint

select to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as rep_start_time from dual;

variable b_snap_id number
variable e_snap_id number

-- Create AWR/Statspack snapshot (or do nothing)
exec :b_snap_id := &snapshot_call

column rep_end_time new_value rep_end_time noprint

select to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as rep_end_time from dual;

column start_time new_value start_time noprint

select to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as start_time from dual;

-- Wait the defined time, default 600 seconds / 10 minutes, take time to create report into account
exec dbms_lock.sleep(greatest(0, &wait_time - ((cast(timestamp '&rep_end_time' as date) - cast(timestamp '&rep_start_time' as date)) * 86400)))

column end_time new_value end_time noprint

select to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as end_time from dual;

-- Create another AWR/Statspack snapshot (or do nothing)
exec :e_snap_id := &snapshot_call

