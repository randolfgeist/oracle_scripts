prompt
prompt Enter a valid TEMPORARY tablespace to assign to the newly created benchmark user
prompt

select tablespace_name from dba_tablespaces where contents = 'TEMPORARY';

accept temp_tablespace prompt 'Enter TEMPORARY tablespace to use: '

