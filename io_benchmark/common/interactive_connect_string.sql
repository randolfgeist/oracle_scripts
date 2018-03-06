prompt
prompt Enter the connection string to use to connect to this database, leave blank for local connection
prompt

accept connect_string prompt 'Enter connection string (no leading @ sign please): '

column connect_string2 new_value connect_string2 noprint

select nvl2('&connect_string', '@&connect_string', '') as connect_string2 from dual;
