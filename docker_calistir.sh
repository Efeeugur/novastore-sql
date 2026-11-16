#!/bin/bash
# NovaStore scriptini Docker icindeki SQL Server 2022'de calistirir.
# Kullanim: bash docker_calistir.sh
# Gereksinim: Docker Desktop acik olmali (Apple Silicon'da Settings > General > "Use Rosetta" isaretli).
set -e
cd "$(dirname "$0")"
[ -f .env ] || { echo ".env yok. .env.example dosyasini .env olarak kopyalayip sifre yazin."; exit 1; }
source .env
AD=novastore-sql
mkdir -p yedek docs

if ! docker ps --format '{{.Names}}' | grep -q "^$AD$"; then
  docker rm -f $AD >/dev/null 2>&1 || true
  echo ">> SQL Server konteyneri baslatiliyor (ilk seferde imaj indirilir, birkac dakika surebilir)..."
  docker run -d --name $AD --platform linux/amd64 \
    -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
    -p 1433:1433 -v "$PWD/yedek:/Yedek" \
    mcr.microsoft.com/mssql/server:2022-latest >/dev/null
fi

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
docker exec $AD test -x $SQLCMD 2>/dev/null || SQLCMD=/opt/mssql-tools/bin/sqlcmd

echo ">> SQL Server'in hazir olmasi bekleniyor..."
for i in $(seq 1 60); do
  if docker exec $AD $SQLCMD -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then OK=1; break; fi
  sleep 3
done
[ "$OK" = 1 ] || { echo "SQL Server baslamadi. Son loglar:"; docker logs --tail 30 $AD; exit 1; }

echo ">> Script calistiriliyor..."
docker cp EfeUgur_NovaStore_Proje.sql $AD:/tmp/novastore.sql
docker exec -u 0 $AD chmod 644 /tmp/novastore.sql
docker exec -u 0 $AD sh -c "chown mssql /Yedek 2>/dev/null; chmod 777 /Yedek 2>/dev/null" || true
docker exec $AD $SQLCMD -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -f 65001 \
  -i /tmp/novastore.sql -o /tmp/cikti.txt || true
docker cp $AD:/tmp/cikti.txt docs/calistirma_ciktisi.txt
echo ">> Bitti. Cikti: docs/calistirma_ciktisi.txt"
echo ">> Hata satiri sayisi (Msg ...): $(grep -c '^Msg ' docs/calistirma_ciktisi.txt || true)"
ls -la yedek 2>/dev/null | tail -n +2
