prompt
prompt Specify if you want to have an AWR or STATSPACK report generated for the run
prompt Valid values are AWR STATSPACK or NONE
prompt Leave blank for default which is derived from V$VERSION, "Enterprise Edition" defaults to AWR, else STATSPACK
prompt

accept perf_report prompt 'Enter report type one of AWR STATSPACK NONE or leave blank for default derived from V$VERSION: '
