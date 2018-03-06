-- Cleanup
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
  end loop;
end;
/
