prompt If you make use of ASMM or AMM (*TARGET parameters) you should be able to set up a separate small buffer cache on the fiy via ALTER SYSTEM SCOPE = MEMORY commands.
prompt If you are doing so and are running RAC, don't forget to do this on *all* instances involved.
prompt This cache could be reset after running the benchmark by setting its size to 0 again.
prompt
prompt Alternatively you can also use a non-default block size tablespace and assign a very small buffer cache for that non-default block size
prompt But this might change the outcome of the benchmark depending how the storage deals with the I/O requests and their size.
prompt
prompt Finally you can opt for creating larger objects if you want to perform a more "real-life" test
prompt and/or deliberately want to test with larger buffer caches and/or avoid caching effects on lower layers.
prompt In that case you can try to make use of the "Parallel Execution" option when running Enterprise Edition to speed up the object creation part.
