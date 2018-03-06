prompt
prompt If you run this script from a remote client and not on the database host itself, enter the O/S this client runs on
prompt Supported O/S is either "Windows" or "Unix", leave blank for default (if you run this script on the database server)
prompt Default is derived from V$VERSION, but this is the database server O/S, not necessarily the client O/S where this script runs on
prompt

accept os_name prompt 'Enter O/S where this script is executed, Windows or Unix (default derived from V$VERSION): '
