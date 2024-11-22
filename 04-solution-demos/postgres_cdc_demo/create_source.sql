-- This query creates a source that connects to locally running PostgreSQL. Make sure to fill in the authentication parameters accordingly. 
CREATE SOURCE postgres_source WITH(
   connector='postgres-cdc',
   hostname='127.0.0.1',
   port='5432',
   username='postgres',
   password='qwerty1245',
   database.name='postgres',
   schema.name='public'
);
