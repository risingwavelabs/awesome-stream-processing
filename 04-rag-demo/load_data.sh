# Database connection parameters
DB_HOST="0.0.0.0"
DB_PORT="4566"
DB_NAME="dev"
DB_USER="root"

# Find all .mdx files and process them
find . -name "*.mdx" | while read -r file; do
    # Get the file content and escape single quotes for SQL
    content=$(cat "$file" | sed "s/'/''/g")
    
    # Create the SQL insert statement
    sql_statement="INSERT INTO documents (file_name, content) VALUES ('$file', '$content')"
    
    # Execute the SQL statement
    echo "$sql_statement" | psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER"
    
    echo "Processed: $file"
done