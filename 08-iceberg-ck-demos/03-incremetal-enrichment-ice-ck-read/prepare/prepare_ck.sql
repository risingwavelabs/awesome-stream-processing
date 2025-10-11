SET allow_experimental_database_iceberg = 1;

CREATE DATABASE lakekeeper_catalog
ENGINE = DataLakeCatalog('http://lakekeeper:8181/catalog/', 'hummockadmin', 'hummockadmin')
SETTINGS catalog_type = 'rest', storage_endpoint = 'http://minio-0:9301/', warehouse = 'risingwave-warehouse';