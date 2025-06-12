echo "⏳ Waiting for RisingWave to be ready..."

for i in {1..10}; do
  if psql -h risingwave -p 4567 -U root -d dev -c '\q' 2>/dev/null; then
    echo "✅ RisingWave is ready!"
    break
  else
    echo "❌ RisingWave not ready (attempt $i), retrying..."
    sleep 3
  fi
done

echo "▶ Running bootstrap.sql..."
psql -h risingwave -p 4567 -U root -d dev < /docker-entrypoint-initdb.d/bootstrap.sql
