# Query the results from the original database

- FDW use RisingWave as a Postgres FDW(Foreign Data Wrapper).
    
    [risingwave-docs/docs/guides/risingwave-as-postgres-fdw.md at wkx/fdw-demo · risingwavelabs/risingwave-docs (github.com)](https://github.com/risingwavelabs/risingwave-docs/blob/wkx/fdw-demo/docs/guides/risingwave-as-postgres-fdw.md)
    
- sink data back to the PG
    
    Sometimes the performance of FDW is not good enough to meet the requirements. So we still need to sink the mv’s result back to the PG.
    
    https://docs.risingwave.com/docs/current/sink-to-postgres/