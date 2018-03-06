-- Wait another five seconds, hopefully clients have shutdown gracefully otherwise cancel / kill them
exec dbms_lock.sleep(5)

-- Cancel / Kill sessions
declare
  e_dbms_system exception;
  pragma exception_init(e_dbms_system, -20002);
  procedure simulate_control_c(v_sid in integer, v_serial in integer) is
    v_status  varchar2(100);
    -- 60 seconds default timeout
    n_timeout number  := 60;
    dt_start  date    := sysdate;
  begin
    -- SID not found
    if v_sid is null then
      raise_application_error(-20001, 'SID: cannot be  NULL');
    else
      -- Set event 10237 to level 1 in session to simulate CONTROL+C
      begin
        execute immediate 'begin sys.dbms_system.set_ev(:v_sid, :v_serial, 10237, 1, ''''); end;' using v_sid, v_serial;
      exception
      when others then
        raise_application_error(-20002, 'Call to DBMS_SYSTEM raises error');
      end;
      -- Check session state
      loop
        begin
          select
                  status
          into
                  v_status
          from
                  v$session
          where
                  sid = v_sid;
        exception
        -- SID no longer found
        when NO_DATA_FOUND then
          --raise_application_error(-20001, 'SID: ' || v_sid || ' no longer found after cancelling');
          null;
        end;

        -- Status no longer active
        -- then set event level to 0 to avoid further cancels
        if v_status != 'ACTIVE' then
          execute immediate 'begin sys.dbms_system.set_ev(:v_sid, :v_serial, 10237, 0, ''''); end;' using v_sid, v_serial;
          exit;
        end if;

        -- Session still active after timeout exceeded
        -- Give up
        if dt_start + (n_timeout / 86400) < sysdate then
          execute immediate 'begin sys.dbms_system.set_ev(:v_sid, :v_serial, 10237, 0, ''''); end;' using v_sid, v_serial;
          --raise_application_error(-20001, 'SID: ' || v_sid || ' still active after ' || n_timeout || ' seconds');
          exit;
        end if;

        -- Back off after 5 seconds
        -- Check only every second from then on
        -- Avoids burning CPU and potential contention by this loop
        -- However this means that more than a single statement potentially
        -- gets cancelled during this second
        if dt_start + (5 / 86400) < sysdate then
          dbms_lock.sleep(1);
        end if;
      end loop;
    end if;
  end;
begin
  for rec in (select sid, serial#, inst_id, 'alter system kill session ''' || sid || ',' || serial# || ',@' || inst_id || '''' as cmd from gv$session where username = user and status = 'ACTIVE' and module = 'SQL*Plus' and action = '&action&testtype')
  --for rec in (select 'alter system disconnect session ''' || sid || ',' || serial# || ''' immediate' as cmd from v$session where username = user and status = 'ACTIVE' and module = 'SQL*Plus' and action = '&action&testtype')
  loop
    -- Attempt to cancel executions in sessions, only if they run on the current node
    if rec.inst_id = to_number(sys_context('USERENV', 'INSTANCE')) then
      begin
        simulate_control_c(rec.sid, rec.serial#);
      -- If DBMS_SYSTEM is not available, attempt to kill session
      exception
      when e_dbms_system then
        -- Attempt to kill sessions, ignore any errors
        begin
          execute immediate rec.cmd;
        exception
        when others then
          null;
        end;
      end;
    -- Sessions running on a different node in RAC will be killed anyway since DBMS_SYSTEM is restricted to local sessions
    else
      -- Attempt to kill sessions, ignore any errors
      begin
        execute immediate rec.cmd;
      exception
      when others then
        null;
      end;
    end if;
  end loop;
end;
/

