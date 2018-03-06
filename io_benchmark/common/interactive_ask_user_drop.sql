pause Hit CTRL+C to cancel, ENTER to continue

accept username default 'IO_TEST' prompt 'User to *drop* and create for benchmark (default IO_TEST): '

prompt
prompt About to DROP user &username now...
prompt

pause Hit CTRL+C to cancel, ENTER to continue

drop user &username cascade;

pause If you just wanted to clean up hit CTRL+C now, ENTER to continue

prompt
prompt Enter password for new user &username now...
prompt

accept pwd prompt 'Password for user &username: ' hide
