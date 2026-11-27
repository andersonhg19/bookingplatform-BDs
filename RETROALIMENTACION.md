# Retroalimentación – Bases de Datos

Calificación por sprint según la rúbrica de cada entrega. Los scripts se ejecutaron en PostgreSQL 16 vacío. Lo que venía de un sprint anterior aparece como sugerencia y no descuenta.

## Sprint 1 — 5.0 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 Entidades y relaciones | Excelente | 1.25 / 1.25 |
| C2 Preguntas clave | Excelente | 0.75 / 0.75 |
| C3 Modelo lógico | Excelente | 1.00 / 1.00 |
| C4 Modelo físico | Excelente | 1.25 / 1.25 |
| C5 Repositorio y documentación | Excelente | 0.75 / 0.75 |

- C1: cardinalidades coinciden con las FK del script, relación por relación.
- C2: 14 preguntas, todas ejecutadas sobre `seed.sql` con filas. Cobertura amplia (ventanas, `EXCEPT`, división relacional).
- Sugerencia: `clients.city` es texto libre mientras `locations` usa el catálogo `cities`.

## Sprint 2 — 5.0 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Excelente | 0.60 / 0.60 |
| C2 Modelo físico | Excelente | 0.80 / 0.80 |
| C3 schema.sql | Excelente | 0.80 / 0.80 |
| C4 Consultas | Excelente | 0.70 / 0.70 |
| C5 Volumen | Excelente | 0.50 / 0.50 |
| C6 Roles y seguridad | Excelente | 0.60 / 0.60 |
| C7 Almacenamiento e índices | Excelente | 0.40 / 0.40 |
| C8 Costo de una consulta | Excelente | 0.30 / 0.30 |
| C9 Optimización algebraica | Excelente | 0.30 / 0.30 |

- C1: 40 relaciones del MER = 40 FK, incluidas las opcionales.
- C3: 32 tablas, 85 índices, 36 triggers sin errores; las 51 violaciones de `pruebas-integridad.sql` se rechazan.
- C7/C8: cálculos contrastados con lo medido en PostgreSQL (`bt_metap`, `EXPLAIN`).
- Sugerencia: evaluar partición por mes de `audit_log_changes`.

## Sprint 3 — 5.0 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Excelente | 0.70 / 0.70 |
| C2 Script refinado | Excelente | 0.80 / 0.80 |
| C3 Triggers | Excelente | 1.10 / 1.10 |
| C4 Procedimientos | Excelente | 1.10 / 1.10 |
| C5 Consultas | Excelente | 0.60 / 0.60 |
| C6 Roles y seguridad | Excelente | 0.70 / 0.70 |

- C1: 45 relaciones = 45 FK. Se justifica también lo que no se tomó de las migraciones V10–V18.
- C3: 8 triggers nuevos y 1 modificado; las 17 violaciones de `pruebas-sprint3.sql` fallan con un mensaje que nombra la HU.
- C4: 5 procedimientos y 4 funciones con parámetros `OUT` y ejemplo; el ciclo completo como `rol_app` corre sin errores.
- C5: 33 consultas, todas con filas.
- C6: EXECUTE revocado a PUBLIC en todas las rutinas propias; privilegios por columna en `bookings`.
- Sugerencia: que el backend use los procedimientos (migración V19+) y se conecte con un usuario de `rol_app`, no como `postgres`.
- Repositorio: los 7 commits del sprint en un solo día.

## Nota final: 5.0

Promedio simple de los tres sprints.
