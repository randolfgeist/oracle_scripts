-- Create snapshot of GV$EVENT_HISTOGRAM_MICRO
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
  exec_ignore_fail('drop table event_histogram_micro&&ehm_instance');

  execute immediate '
create table event_histogram_micro&&ehm_instance as select * from GV$EVENT_HISTOGRAM_MICRO where event in (''db file scattered read'', ''cell multiblock physical read'')
';
end;
/

