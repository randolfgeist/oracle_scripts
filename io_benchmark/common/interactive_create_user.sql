prompt
prompt About to CREATE user &&username now...
prompt

pause Hit CTRL+C to cancel, ENTER to continue

create user &username identified by &pwd default tablespace &&tablespace_name temporary tablespace &temp_tablespace quota unlimited on &&tablespace_name;

grant create session, create table to &username;

grant select on GV_$EVENT_HISTOGRAM_MICRO to &username;

grant select on V_$SESSION to &username;

grant select on GV_$SESSION to &username;

grant select on V_$INSTANCE to &username;

grant select on GV_$INSTANCE to &username;

grant select on V_$DATABASE to &username;

grant select on AWR_PDB_SNAPSHOT to &username;

grant select on DBA_HIST_SNAPSHOT to &username;

grant select on GV_$CON_SYSMETRIC_HISTORY to &username;

grant select on GV_$SYSMETRIC_HISTORY to &username;

grant execute on DBMS_LOCK to &username;

grant execute on DBMS_WORKLOAD_REPOSITORY to &username;

grant execute on DBMS_SYSTEM to &username;

grant execute on PERFSTAT.STATSPACK to &username;
