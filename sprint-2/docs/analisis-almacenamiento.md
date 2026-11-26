# Análisis de almacenamiento, costo y optimización

Sprint 2 · Bases de Datos · CodeF@ctory 2026-II

Este documento cubre los criterios 7, 8 y 9 de la rúbrica. Hago todos los cálculos con las fórmulas de
referencia del curso y después los comparo con lo que mide PostgreSQL. Para medir llené una base
con el volumen estimado para el final del primer año usando
[`generar-volumen.sql`](generar-volumen.sql), que usa una semilla fija para que los conteos se puedan
reproducir. Los `uuid` sí salen distintos en cada corrida, así que el tamaño exacto de un índice sobre
`id` puede variar unas pocas páginas.

| Dato | Valor |
|---|---|
| Tabla analizada | `bookings` |
| Volumen (fin del año 1) | TR = 1 584 000 reservas y 1 435 500 sesiones, de la [estimación de volumen](../README.md#5-estimación-de-volumen) |
| Tamaño de página | P = B = 8 192 bytes, el bloque de PostgreSQL |
| Memoria para operaciones | M = 512 páginas, los 4 MB de `work_mem` por defecto |

## 1. Por qué `bookings`

Es la tabla central del sistema. El historial del cliente, los reportes del proveedor, los pagos y
las reseñas pasan por ella. Hay tablas que crecen más, como `booking_status_changes`, `payments` o la
auditoría. Las dos primeras cuelgan de `bookings` y se consultan a través de ella, y la auditoría sólo
la lee el administrador.

Al normalizar, `bookings` le pasó a `sessions` el servicio, la sede y el horario, que dependían de la
sesión y no de la reserva. Eso la hizo más angosta, y se nota en el cálculo de abajo.

## 2. Organización del archivo e índices

**Archivo de montículo (heap).** Es la única organización que PostgreSQL ofrece para una tabla, y en
este caso es la que conviene. Las reservas llegan en cualquier orden de sesión y de cliente, así que
ningún orden físico favorece a todas las consultas a la vez. El comando `CLUSTER` ordena la tabla una
sola vez y no mantiene ese orden con las inserciones nuevas, por eso no lo uso.

**Cluster multitabla.** Tampoco lo uso. PostgreSQL no tiene clusters multitabla al estilo de Oracle.
Si los tuviera, el candidato sería `sessions` con `bookings` por `session_id`, porque las reservas de
una sesión se leen juntas. Pero una sesión tiene en promedio 1,1 reservas, así que el ahorro sería
mínimo.

**Índices.** Todos son árboles B+. La tabla casi nunca se lee entera, sino por una sesión o por un
cliente:

| Índice | Columnas | Lo usa |
|---|---|---|
| `pk_bookings` | `id` | buscar una reserva; destino de las FK de pagos, reseñas, historial y lista de espera |
| `ix_bookings_session` | `session_id` | pasar de una sesión a sus reservas, como en la consulta de la sección 4, y el trigger de cupo, que suma los asistentes de una sesión |
| `ix_bookings_client` | `client_id` | historial de reservas de un cliente |
| `ix_bookings_policy` | `policy_id` | la FK hacia la política |

Y en `sessions`, que es por donde se filtra por fecha:

| Índice | Columnas | Lo usa |
|---|---|---|
| `ix_sessions_service_starts` | `service_id, starts_at` | la FK por servicio (es el prefijo) y los reportes de un servicio en un rango de fechas |
| `ix_sessions_location_starts` | `location_id, starts_at` | agenda y ocupación de una sede |

El equipo tenía un índice sólo sobre `service_id` en las reservas. Lo cambié por
`(service_id, starts_at)`, ahora en `sessions`: sirve a lo mismo, porque `service_id` es su prefijo,
y además deja que el filtro de fechas entre en la búsqueda. La sección 4 muestra lo que gana.

No uso índices hash porque los árboles B también sirven para rangos de fechas. Tampoco uso BRIN: las
fechas de las sesiones no llegan en orden, porque hoy se reserva para dentro de un mes.

## 3. Estimación de la tabla y de un índice

### 3.1 Longitud del registro (L)

`L = 4 × #campos variables + size(campos fijos) + size(mapa de bits) + tamaño estimado(campos variables)`

| Campo | Tipo | Bytes | |
|---|---|---|---|
| `id`, `client_id`, `session_id`, `policy_id`, `currency_id` | `uuid` | 5 × 16 = 80 | fijo |
| `cancelled_at`, `created_at`, `updated_at` | `timestamptz` | 3 × 8 = 24 | fijo |
| `attendees` | `integer` | 4 | fijo |
| `total_price` | `numeric(12,2)` | ≈ 8 | variable |
| `status` | `varchar(20)` | ≈ 9 | variable: `CONFIRMED` y `COMPLETED` tienen 9 letras |

- Campos fijos: 80 + 24 + 4 = **108 bytes**
- Campos variables: 2, que cuestan 4 × 2 = **8 bytes** de prefijo
- Mapa de bits de nulos: 11 campos, ⌈11 / 8⌉ = **2 bytes**
- Tamaño estimado de los variables: 8 + 9 = **17 bytes**

**L = 8 + 108 + 2 + 17 = 135 bytes**

En la versión anterior del modelo la reserva medía 183 bytes. Los 48 que se fueron son `service_id`,
`location_id`, `starts_at` y `ends_at` (16 + 16 + 8 + 8), que ahora se guardan una sola vez por sesión.

### 3.2 Registros por bloque (FR) y páginas (BR)

`P = 2 + 4·FR + FR·L`, de donde `FR = ⌊(P − 2) / (4 + L)⌋`

FR = ⌊(8 192 − 2) / (4 + 135)⌋ = ⌊8 190 / 139⌋ = ⌊58,92⌋ = **58 registros por página**

`BR = ⌈TR / FR⌉`

BR = ⌈1 584 000 / 58⌉ = ⌈27 310,3⌉ = **27 311 páginas**

Espacio de la tabla = 27 311 × 8 192 bytes = 223 731 712 bytes ≈ **213 MB**

### 3.3 Índice `pk_bookings`

Elijo el índice de la clave primaria porque es el que usan todas las claves foráneas que apuntan a
una reserva, y porque cada reserva es un valor distinto: V(id, bookings) = TR.

**Entradas por nodo.** Cada entrada guarda la clave y un puntero a la tupla. Tomo 6 bytes para el
puntero, que es lo que mide un TID de PostgreSQL (bloque + posición).

- L del índice = 16 (`uuid`) + 6 (puntero) = 22 bytes
- FR = ⌊B / L⌋ = ⌊8 192 / 22⌋ = **372 entradas por nodo**

**Orden del árbol.** 2d − 1 = FR → 2d − 1 = 372 → d = 186,5 → **d = 186** (cumple d ≥ 3)

**Altura.** `H ≤ log_d V(a,R)`

log₁₈₆ 1 584 000 = ln 1 584 000 / ln 186 = 14,275 / 5,226 = 2,73

Un árbol no tiene niveles fraccionarios, así que el resultado se redondea hacia arriba. Dos niveles no
alcanzan ni con los nodos llenos: 372 × 372 = 138 384 entradas, muy por debajo de 1 584 000. Con tres
sí. H = ⌈2,73⌉ = **3 niveles**, que es lo que da también la tabla de nodos por nivel.

**Nodos por nivel.** `nodos del nivel k ≤ V(a,R) / d^k`, contando desde las hojas

| Nivel | Cálculo | Nodos |
|---|---|---|
| 1 (hojas) | 1 584 000 / 186 = 8 516,1 | 8 517 |
| 2 | 1 584 000 / 186² = 1 584 000 / 34 596 = 45,8 | 46 |
| 3 (raíz) | 1 584 000 / 186³ = 0,25 | 1 |
| **Total** | | **8 564** |

**Espacio.** `Espacio = (Σ nodos de todos los niveles) × B` = 8 564 × 8 192 = 70 156 288 bytes ≈ **67 MB**

Es una cota superior. La fórmula supone que cada nodo tiene sólo el mínimo de d entradas, es decir,
que está lleno a la mitad.

`ix_bookings_session` tiene la misma forma, una clave `uuid` de 16 bytes, y lo uso en la sección 4.
Su V(session_id, bookings) es 1 435 500 y no 1 584 000, porque las reservas de un taller comparten
sesión: log₁₈₆ 1 435 500 = 2,71, así que también tiene 3 niveles. Eso sí, guarda una entrada por
reserva, así que ocupa casi lo mismo que `pk_bookings`.

### 3.4 Lo que mide PostgreSQL

Con las 1 584 000 reservas cargadas en orden aleatorio, como llegarían en producción:

| Medida | Calculado | Medido | Diferencia |
|---|---|---|---|
| Páginas de `bookings` | 27 311 | 30 462 | +11,5 % |
| Registros por página | 58 | 52 | |
| Altura de `pk_bookings` | 3 | 3 (raíz en el nivel 2 de `bt_metap`) | igual |
| Páginas de `pk_bookings` | ≤ 8 564 | 8 075 | dentro de la cota |

La tabla mide un 11,5 % más porque PostgreSQL le pone a cada tupla una cabecera de 23 bytes y a cada
página una de 24, y la fórmula del curso no las cuenta. Con la fila real de 152 bytes que mide
`pg_column_size`, la misma fórmula da ⌊8 168 / 156⌋ = 52 registros por página y
⌈1 584 000 / 52⌉ = 30 462 páginas, justo lo medido. En una fila corta como esta la cabecera pesa
mucho: es casi un 16 % de la tupla.

El índice también se explica por lo que la fórmula no cuenta. Una entrada real mide 28 bytes y no 22:
8 de cabecera de la tupla del índice, 16 de la clave y 4 del puntero de línea de la página. Una hoja
llena tendría unas 290 entradas, y las medidas tienen en promedio 1 584 000 / 8 075 = 196, un 67 %.
Es lo que pasa con claves que llegan en desorden, como los `uuid`: cada vez que una hoja se llena se
parte en dos mitades. Si las reservas llegaran ordenadas por `id`, el índice se llenaría casi entero
y mediría bastante menos.

## 4. Costo de una consulta con reunión

### 4.1 La consulta

*¿Cuántas reservas e ingresos dejó cada servicio de un proveedor en el mes?* Es la consulta 24 de
[`consultas.sql`](../consultas.sql), el reporte mensual que ve el dueño del negocio. Aquí la escribo
con el proveedor como parámetro y un mes fijo, que es como la corrí contra la base de volumen.

```sql
select s.name as servicio, count(*) as reservas, sum(b.total_price) as ingresos
from services s
    inner join sessions se on se.service_id = s.id
    inner join bookings b  on b.session_id  = se.id
where s.organization_id = :proveedor
  and se.starts_at >= '2026-10-01' and se.starts_at < '2026-11-01'
  and b.status in ('CONFIRMED', 'COMPLETED')
group by s.name
order by ingresos desc;
```

Son dos reuniones: servicios con sesiones, por `service_id`, y sesiones con reservas, por
`session_id`. El filtro del proveedor cae en `services`, el del mes en `sessions` y el del estado en
`bookings`.

### 4.2 Estadísticas y de dónde salen

**Páginas de `services` (BS)**, con el mismo método de la sección 3.1:

- Fijos: `id`, `organization_id` y `currency_id` (3 × 16 = 48), `duration_minutes`,
  `preparation_minutes`, `cleanup_minutes` y `customer_capacity` (4 × 4 = 16), `created_at` y
  `updated_at` (2 × 8 = 16): **80 bytes**
- Variables: `name` ≈ 20, `description` ≈ 60, `price` ≈ 8 y `status` ≈ 6: **94 bytes**, con un
  prefijo de 4 × 4 = **16 bytes**
- Mapa de bits: 13 campos, ⌈13 / 8⌉ = **2 bytes**
- L = 16 + 80 + 2 + 94 = **192 bytes** → FR = ⌊8 190 / 196⌋ = 41 → BS = ⌈5 440 / 41⌉ = **133 páginas**

**Páginas de `sessions` (BSe):**

- Fijos: `id`, `service_id` y `location_id` (3 × 16 = 48), `starts_at`, `ends_at`, `created_at` y
  `updated_at` (4 × 8 = 32): **80 bytes**
- No tiene campos variables, así que no hay prefijo
- Mapa de bits: 7 campos, ⌈7 / 8⌉ = **1 byte**
- L = 0 + 80 + 1 + 0 = **81 bytes** → FR = ⌊8 190 / 85⌋ = 96 → BSe = ⌈1 435 500 / 96⌉ = **14 954 páginas**

| Estadística | Valor | De dónde sale |
|---|---|---|
| TS (services) | 5 440 | 680 proveedores × 8 servicios |
| BS (services) | 133 | arriba |
| V(organization_id, services) | 680 | un valor por proveedor |
| S(organization_id, services) | 5 440 / 680 = 8 | servicios de un proveedor |
| TSe (sessions) | 1 435 500 | estimación de volumen del README |
| BSe (sessions) | 14 954 | arriba |
| V(service_id, sessions) | 5 440 | todo servicio tiene sesiones |
| S(service_id, sessions) | 1 435 500 / 5 440 = 263,9 ≈ 264 | sesiones por servicio |
| Fracción del mes | c = 1/12 | sesiones repartidas parejo en el año |
| Sesiones de un servicio en el mes | 264 × 1/12 = 22 | S(service_id, sessions) por la fracción del mes |
| TR (bookings) | 1 584 000 | estimación de volumen del README |
| BR (bookings) | 27 311 | sección 3.2 |
| V(session_id, bookings) | 1 435 500 | toda sesión tiene al menos una reserva |
| S(session_id, bookings) | 1 584 000 / 1 435 500 = 1,10 | reservas por sesión |
| Fracción de estados | 0,75 | supuesto: 60 % `COMPLETED` + 15 % `CONFIRMED` |
| HI de `uk_services_org_name` | 2 | entrada de 16 + 20 + 6 = 42 bytes → FR = 195, d = 98 → ⌈log₉₈ 5 440⌉ = ⌈1,88⌉ = 2 |
| HI de `ix_sessions_service_starts` | 3 | entrada de 16 + 8 + 6 = 30 bytes → FR = 273, d = 137 → ⌈log₁₃₇ 1 435 500⌉ = ⌈2,88⌉ = 3 |
| HI de `ix_bookings_session` | 3 | igual que `pk_bookings`, sección 3.3 |

En la base de volumen, `bt_metap` confirma las tres alturas (2, 3 y 3), el estado da 0,749 y
`pg_stats` da para `services.organization_id` −0,125, que PostgreSQL usa para decir "una fracción de
las filas": 0,125 × 5 440 = 680. Para `sessions.service_id` da 5 342 y para `bookings.session_id`
1 171 935, un poco por debajo de los valores reales (5 440 y 1 435 500) porque los estima con una
muestra de 30 000 filas.

**Un supuesto que conviene decir.** Estas estadísticas son las del final del año: 680 proveedores y
las reservas acumuladas de todo el año. Repartidas así salen 8 × 22 × 1,10 ≈ 194 reservas al mes por
proveedor, menos que las 300 del supuesto de volumen. No es una contradicción: las 300 son de un
proveedor que lleva todo el año, y aquí el promedio incluye a los que llegaron a mitad de camino. La
base de volumen da lo mismo, 194 reservas por proveedor en un mes.

**Tamaño de la salida.** Las dos reuniones van de una clave foránea a la clave que referencia, así
que ninguna multiplica filas por encima de la tabla del lado de la FK. Con los filtros quedan
8 servicios × 22 sesiones × 1,10 reservas × 0,75 ≈ **146 tuplas**.

### 4.3 Alternativas de ejecución

Para las dos reuniones, la relación pequeña que sale de la primera (176 sesiones) cabe en memoria,
así que no la vuelvo a contar como lectura en la segunda.

**A. Ciclos anidados por bloques, sin índices.** `services` va como externa porque es la pequeña. Sus
133 páginas caben en las M − 2 = 510 páginas de memoria, así que `sessions` se recorre una sola vez:

Costo de la primera reunión = BS + BSe × ⌈BS / (M − 2)⌉ = 133 + 14 954 × ⌈133 / 510⌉ = 133 + 14 954 = 15 087

Las 176 sesiones que quedan caben en memoria, así que `bookings` también se recorre una vez:

Costo = 15 087 + 27 311 = **42 398 páginas**

**B. Ciclos anidados con índice, filtrando primero.** `Costo = BT + TT × S(b,R)`, aplicada dos veces.

Primero saco los servicios del proveedor con el índice secundario `uk_services_org_name`:

Costo de obtener los servicios = HI + S(organization_id, services) = 2 + 8 = 10 páginas

Por cada servicio busco sus sesiones del mes en `sessions`, y por cada sesión sus reservas en
`bookings`. Supongo el peor caso: cada tupla en una página distinta, que es lo esperable porque las
sesiones de un servicio llegan revueltas con las demás. Hay dos variantes, según el índice de
`sessions`:

*B1. Con un índice sólo sobre `service_id`, como el que tenía el equipo.* Cada búsqueda trae las 264
sesiones del servicio y el filtro de fechas se aplica después, sobre las tuplas leídas:

Costo de la primera reunión = BT + TT × (HI + S) = 10 + 8 × (3 + 264) = 10 + 2 136 = 2 146 páginas

*B2. Con el índice `(service_id, starts_at)` de este esquema.* Dentro de las entradas de cada servicio,
las fechas están ordenadas, así que la búsqueda es una selección por rango sobre el árbol B+:
HI + LB·c + TR·c, con TR = 264 y c = 1/12. Las entradas de un servicio caben en una hoja, así que LB·c
es menos de una página y lo redondeo a 0:

Costo por búsqueda = 3 + 0 + 264 × 1/12 = 3 + 22 = 25 páginas

Costo de la primera reunión = BT + TT × 25 = 10 + 8 × 25 = 210 páginas

Las dos variantes entregan las mismas 8 × 22 = 176 sesiones, y la segunda reunión cuesta lo mismo en
las dos. Por cada sesión busco sus reservas en `ix_bookings_session`. La fórmula de referencia da
TT × S(session_id, bookings) = 176 × 1,10 = 194 páginas, pero no cuenta el descenso por el índice en
cada búsqueda. Aquí sí importa: cada búsqueda trae sólo 1,1 tuplas y baja 3 niveles para encontrarlas.
Con el descenso:

Costo de la segunda reunión = TT × (HI + S) = 176 × (3 + 1,10) = 722 páginas

| Variante | Primera reunión | Segunda reunión | Total sin descenso | **Total con descenso** |
|---|---|---|---|---|
| B1 | 10 + 8 × 264 = 2 122 | 194 | 2 316 | **2 146 + 722 = 2 868** |
| B2 | 10 + 8 × 22 = 186 | 194 | 380 | **210 + 722 = 932** |

En la columna sin descenso tampoco sumo la HI de `ix_sessions_service_starts` en cada búsqueda, para
que las dos columnas apliquen el mismo criterio.

El filtro de estado se aplica sobre las reservas leídas.

**C. Reunión por hash.** Las dos tablas hash se arman con lo pequeño: los 8 servicios del proveedor
primero y las 176 sesiones después, y las dos caben de sobra en memoria. Entonces es la variante en
memoria: se recorre `sessions` una vez para la primera reunión y `bookings` una vez para la segunda.

Costo = 10 + BSe + BR = 10 + 14 954 + 27 311 = **42 275 páginas**

Si lo pequeño no cupiera en memoria haría falta el Grace hash join, que exige M > √BR
(512 > √27 311 = 165, se cumple) y cuesta 3 veces más.

**D. Ordenamiento y mezcla.** Con ⌈log₅₁₁ 133⌉ = 1 pasada para `services`, ⌈log₅₁₁ 14 954⌉ = 2 para
`sessions` y ⌈log₅₁₁ 27 311⌉ = 2 para `bookings`. Las 176 sesiones del medio caben en una página:

Primera reunión = 133 + 14 954 + 2·133·1 + 2·14 954·2 = 75 169 páginas

Segunda reunión = 1 + 27 311 + 2·1·1 + 2·27 311·2 = 136 558 páginas

Costo = 75 169 + 136 558 = **211 727 páginas**

### 4.4 Comparación

Medí cada plan con `EXPLAIN (ANALYZE, BUFFERS)`, sumando las páginas leídas del disco y las que ya
estaban en memoria, para un proveedor de la base de volumen:

| Alternativa | Costo calculado (páginas) | Medido en PostgreSQL |
|---|---|---|
| A. Ciclos anidados por bloques | 42 398 | |
| B1. Ciclos anidados con índice sobre `service_id` | 2 868 | 2 847, con ese índice creado para medir |
| **B2. Ciclos anidados con índice `(service_id, starts_at)`** | **932** | **989**, el plan que elige el optimizador |
| C. Hash, en memoria | 42 275 | 49 688, forzado con `enable_nestloop = off` |
| D. Ordenamiento y mezcla | 211 727 | |

B2 es unas 45 veces más barata que A o C, y tres veces más barata que B1. A y C leen las dos tablas
grandes enteras para quedarse con 146 filas. B1 sólo lee las sesiones de 8 servicios de 5 440, pero
de todo el año. B2 lee sólo las del mes.

El `EXPLAIN` de B2 lo confirma paso por paso: 10 páginas de `services`, 25 del índice de sesiones y
186 de `sessions`, y 768 para pasar de 186 sesiones a sus reservas, que son 4,13 páginas por
búsqueda, casi las 3 + 1,10 calculadas. Este proveedor tiene 186 sesiones en octubre y no 176
porque octubre tiene 31 días y no 30,4. La medición de C da más que el cálculo porque las tablas
reales tienen 30 462 y 19 140 páginas, y no 27 311 y 14 954 (sección 3.4).

**Lo que cuesta el índice compuesto.** Mide 72 MB, frente a los 10 MB del de una sola columna. Como lo
reemplaza, cada sesión nueva sigue actualizando un solo índice por servicio. En la primera reunión
lee diez veces menos (210 páginas contra 2 146), y en la consulta completa, tres veces menos. Pagar
62 MB por eso en todos los reportes por servicio y fecha me parece un buen negocio, y por eso lo dejé
en el esquema.

## 5. Optimización algebraica

Uso la notación del curso. `bookings`, `sessions` y `services` comparten los nombres `id`,
`created_at` y `updated_at`, y además `bookings` y `services` comparten `currency_id` y `status`. El
producto cartesiano exige cabeceras sin nombres repetidos, así que renombro `sessions` y `services`
antes del producto:

```
Se ← ρSe(se_id, se_service, se_location, se_starts, se_ends, se_created, se_updated)(sessions)
S  ← ρS(s_id, s_org, s_name, s_description, s_duration, s_preparation, s_cleanup,
        s_price, s_currency, s_capacity, s_status, s_created, s_updated)(services)
B  ← bookings
```

Abrevio los predicados:

- p₁: `session_id = se_id`
- p₂: `se_service = s_id`
- p₃: `s_org = X`
- p₄: `se_starts ≥ '2026-10-01' ∧ se_starts < '2026-11-01'`
- p₅: `status ∈ {CONFIRMED, COMPLETED}`

### 5.1 Expresión inicial

La traducción directa del SQL: el `from` es un producto, el `where` una restricción y el `group by`
un agrupamiento.

```
E₀ = s_name Ģ COUNT(*) AS reservas, SUM(total_price) AS ingresos ( σ p₁ ∧ p₂ ∧ p₃ ∧ p₄ ∧ p₅ (B × Se × S) )
```

El producto genera 1 584 000 × 1 435 500 × 5 440 ≈ **1,24 × 10¹⁶ tuplas** antes de filtrar nada.

### 5.2 Transformaciones

**Paso 1. Ley 2, selección conjunta.** Parto la restricción en una cascada para poder mover cada
parte por separado. Como ∧ es conmutativa, la ley 2 también deja escoger el orden de la cascada.
Pongo abajo p₅ y p₄, que van a bajar más lejos.

```
Ģ ( σ p₁ ( σ p₂ ( σ p₃ ( σ p₄ ( σ p₅ ( B × Se × S ) ) ) ) ) )
```

**Paso 2. Ley 12, asociatividad.** Como las tres cabeceras ya no comparten nombres, la reunión
natural entre ellas es un producto, y la ley 12 deja agruparlas como convenga. Agrupo `Se` con `S`
porque p₂ las une a las dos y no toca a `B`:

```
Ģ ( σ p₁ ( σ p₂ ( σ p₃ ( σ p₄ ( σ p₅ ( B × ( Se × S ) ) ) ) ) ) )
```

**Paso 3. Leyes 4 y 5, selección sobre un producto.** La tabla de referencia las enuncia para ⋈; las
aplico sobre × porque, con las cabeceras renombradas, el ⋈ de estas relaciones es un ×. Cada predicado
baja hasta la relación cuyos atributos usa. p₅ sólo usa `status`, de `B`. p₄ sólo usa `se_starts`, de `Se`. p₃ sólo usa `s_org`, de
`S`. p₂ usa `Se` y `S`, así que baja hasta su producto. p₁ usa `B` y `Se`, y se queda arriba.

```
Ģ ( σ p₁ ( σ p₅ (B) × σ p₂ ( σ p₄ (Se) × σ p₃ (S) ) ) )
```

**Paso 4. Definición de reunión theta.** Una restricción sobre un producto es una reunión:
σ condición (R₁ × R₂) ≡ R₁ θ condición R₂. Se aplica dos veces:

```
Ģ ( σ p₅ (B)  θ p₁  ( σ p₄ (Se)  θ p₂  σ p₃ (S) ) )
```

**Paso 5. Una proyección debajo del agrupamiento.** Este paso no es una de las leyes de la tabla de
referencia, que no tratan el agrupamiento. Se apoya en cómo está definido Ģ: el resultado sólo depende
de los atributos de agrupamiento (`s_name`) y de los que agrega (`total_price`), así que puedo
proyectar antes sin cambiar el resultado. Hay un cuidado: π elimina tuplas repetidas, y dos reservas
del mismo servicio con el mismo precio quedarían en una sola, con lo que `COUNT(*)` y `SUM` darían
mal. Para no perderlas conservo la clave `id` de la reserva.

```
Ģ ( π id, s_name, total_price ( σ p₅ (B)  θ p₁  ( σ p₄ (Se)  θ p₂  σ p₃ (S) ) ) )
```

**Paso 6. Ley 9, proyección sobre una reunión.** La proyección se reparte entre los lados de cada
reunión. Cada lado conserva los atributos que su reunión necesita: `session_id` y `se_id` para p₁,
`se_service` y `s_id` para p₂. Arriba queda la proyección original, que los descarta al final.

```
Ģ ( π id, s_name, total_price (
      π id, session_id, total_price ( σ p₅ (B) )
      θ p₁
      π se_id, s_name ( π se_id, se_service ( σ p₄ (Se) )  θ p₂  π s_id, s_name ( σ p₃ (S) ) ) ) )
```

**Paso 7. Leyes 3 y 8, la proyección baja de la restricción.** En el lado de B, p₅ usa `status`. Por la
ley 3, una proyección que conserve ese atributo conmuta con la restricción:

π id, session_id, total_price, status (σ p₅ (B)) ≡ σ p₅ (π id, session_id, total_price, status (B))

Y por la ley 8, proyectar primero sobre esos cuatro atributos y después sobre tres es lo mismo que
proyectar directamente sobre los tres. Juntas:

π id, session_id, total_price (σ p₅ (B)) ≡ π id, session_id, total_price (σ p₅ (π id, session_id, total_price, status (B)))

Lo mismo en `Se`, conservando `se_starts`, y en `S`, conservando `s_org`. Con esto cada tupla deja
atrás las columnas que no se van a usar desde que se lee de la tabla.

**Paso 8. Leyes 11 y 12, orden de las reuniones.** El orden importa por el tamaño de lo que queda en
medio. Hay dos opciones razonables:

- Unir primero B con Se: σ p₅ (B) θ p₁ σ p₄ (Se) deja las reservas vivas o atendidas del mes de todos
  los proveedores, 1 584 000 × 0,75 × 1/12 = **99 000 tuplas**, y sólo después se descartan las de
  otros proveedores.
- Unir primero Se con S: σ p₄ (Se) θ p₂ σ p₃ (S) deja las sesiones del mes de este proveedor,
  8 × 22 = **176 tuplas**.

Me quedo con la segunda, que es la que ya tiene la expresión del paso 6, y con la ley 11 pongo la
relación pequeña a la izquierda de cada reunión. Es la externa de cada ciclo anidado de B2 en la
sección 4.3.

### 5.3 Expresión optimizada

```
E₁ = s_name Ģ COUNT(*) AS reservas, SUM(total_price) AS ingresos (
       π id, s_name, total_price (
           π se_id, s_name (
               π s_id, s_name ( σ s_org = X ( π s_id, s_name, s_org (S) ) )
               θ s_id = se_service
               π se_id, se_service ( σ p₄ ( π se_id, se_service, se_starts (Se) ) ) )
           θ se_id = session_id
           π id, session_id, total_price ( σ p₅ ( π id, session_id, total_price, status (B) ) ) ) )
```

El `order by` no es una operación del álgebra relacional, que trabaja con conjuntos. Se aplica al
final sobre las 8 filas del resultado.

### 5.4 Por qué es más barata

| Medida | E₀ | E₁ |
|---|---|---|
| Tuplas que salen de S hacia las reuniones | 5 440 | 8 |
| Tuplas que salen de Se | 1 435 500 | 1 435 500 × 1/12 = 119 625 |
| Tuplas que salen de B | 1 584 000 | 1 584 000 × 0,75 = 1 188 000 |
| Tamaño de cada tupla que sube (S, Se, B) | 192, 81 y 135 bytes | 36, 32 y 40 bytes |
| Tuplas que genera el producto o la primera reunión | 1,24 × 10¹⁶ | 176 |
| Tuplas que genera la segunda reunión | | 146 |
| Tuplas que llegan al agrupamiento | 146 | 146 |

El resultado es el mismo. E₀ arma más de diez mil billones de combinaciones para quedarse con 146.
En E₁ los filtros actúan antes de las reuniones y el orden elegido deja sólo 176 tuplas en medio, en
vez de 99 000. Las proyecciones además reducen cada tupla a lo que la consulta usa: una reserva pasa
de 135 a 40 bytes (16 de `id`, 16 de `session_id` y 8 de `total_price`), una sesión de 81 a 32 y un
servicio de 192 a 36.

En la base de volumen, σ p₄ (Se) da 121 978 tuplas, σ p₅ (B) 1 186 686, la primera reunión 186 y la
segunda 161. Había estimado 119 625, 1 188 000, 176 y 146. La reunión en el otro orden, B con Se
primero, daría 100 943 tuplas en medio; había estimado 99 000.

El plan que ejecuta PostgreSQL, el B2 de la sección 4.3, es la forma física de E₁. No materializa las
restricciones enteras: usa `uk_services_org_name` para aplicar p₃, el índice `(service_id, starts_at)`
para aplicar p₄ dentro de la búsqueda de cada uno de los 8 servicios, y p₅ al leer cada reserva. Y
une en el mismo orden: servicios, después sesiones y al final reservas. Es decir, hace las
restricciones antes de las reuniones, que es justo lo que pide la heurística.
