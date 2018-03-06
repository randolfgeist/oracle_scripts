prompt
prompt The purpose of this script here is to simplify usage of the actual benchmark script and to *DROP* and re-create a suitable user for running the benchmark.
prompt
prompt Note: The benchmark script can make use of AWR views and call DBMS_WORKLOAD_REPOSITORY.
prompt If you allow it doing so please ensure that you have either a Diagnostic Pack license or switched off AWR functionality via the CONTROL_MANAGEMENT_PACK_ACCESS parameter to avoid licensing issues.
prompt STATSPACK report generation option is also available
prompt
prompt This script should be executed as SYSDBA because grants on SYS owned objects like DBMS_LOCK and DBMS_SYSTEM are required.
prompt
prompt It prompts several questions used as parameters for the actual benchmark script and shows along some information about required and available space.
