Scripts que Postgres corre en el primer arranque (volumen vacío), en orden
alfabético. `01-verdicts-schema.sql` sale de:

    docker compose exec -T postgres pg_dump -U soar -d soar -t verdicts --schema-only > sql/01-verdicts-schema.sql

Solo estructura, sin datos: el cache se llena solo.
