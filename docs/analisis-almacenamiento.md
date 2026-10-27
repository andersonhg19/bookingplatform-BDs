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
| Volumen (fin del año 1) | TR = 1 584 000 reservas, de la [estimación de volumen](../README.md#5-estimación-de-volumen) |
| Tamaño de página | P = B = 8 192 bytes, el bloque de PostgreSQL |
| Memoria para operaciones | M = 512 páginas, los 4 MB de `work_mem` por defecto |

## 1. Por qué `bookings`

Es la tabla central del sistema. El catálogo de disponibilidad, el historial del cliente, los
reportes del proveedor y los pagos pasan por ella. Hay tablas que crecen más, como
`booking_status_changes`, `payments` o `audit_log`, pero casi todas cuelgan de `bookings` y se
consultan a través de ella.

## 2. Organización del archivo e índices

**Archivo de montículo (heap).** Es la única organización que PostgreSQL ofrece para una tabla, y en
este caso es la que conviene. Las reservas llegan en cualquier orden de servicio, sede y cliente, así
que ningún orden físico favorece a todas las consultas a la vez. El comando `CLUSTER` ordena la tabla
una sola vez y no mantiene ese orden con las inserciones nuevas, por eso no lo uso.

**Cluster multitabla.** Tampoco lo uso. PostgreSQL no tiene clusters multitabla al estilo de Oracle.
Si los tuviera, juntar `services` con `bookings` por `service_id` metería unas 292 reservas detrás de
cada servicio, y leer el catálogo de servicios obligaría a pasar por encima de todas ellas.

**Índices.** Todos son árboles B+. La tabla casi nunca se lee entera, sino por un servicio, un cliente
o una sede:

| Índice | Columnas | Lo usa |
|---|---|---|
| `pk_bookings` | `id` | buscar una reserva; destino de las FK de pagos, reseñas e historial |
| `uk_bookings_snapshot` | `id, session_id, starts_at, ends_at, status` | destino de la FK compuesta de `booking_resources` |
| `ix_bookings_client_starts` | `client_id, starts_at desc` | historial de reservas de un cliente |
| `ix_bookings_location_starts` | `location_id, starts_at` | agenda y ocupación de una sede |
| `ix_bookings_service_starts` | `service_id, starts_at` | la FK por servicio (es el prefijo) y los reportes de un servicio en un rango de fechas, como la consulta de la sección 4 |
| `ix_bookings_session` | `session_id` | el trigger de cupo suma los asistentes de una sesión |
| `ix_bookings_policy` | `policy_id` | la FK hacia la política |

El equipo tenía un índice sólo sobre `service_id`. Lo cambié por `(service_id, starts_at)`: sirve a
lo mismo, porque `service_id` es su prefijo, y además deja que el filtro de fechas entre en la búsqueda.
La sección 4 muestra lo que gana.

No uso índices hash porque los árboles B también sirven para rangos de fechas. Tampoco uso BRIN: las
fechas de reserva no llegan en orden, porque hoy se reserva para dentro de un mes.

## 3. Estimación de la tabla y de un índice

### 3.1 Longitud del registro (L)

`L = 4 × #campos variables + size(campos fijos) + size(mapa de bits) + tamaño estimado(campos variables)`

| Campo | Tipo | Bytes | |
|---|---|---|---|
| `id`, `client_id`, `service_id`, `location_id`, `policy_id`, `session_id`, `currency_id` | `uuid` | 7 × 16 = 112 | fijo |
| `starts_at`, `ends_at`, `cancelled_at`, `created_at`, `updated_at` | `timestamptz` | 5 × 8 = 40 | fijo |
| `attendees` | `integer` | 4 | fijo |
| `total_price` | `numeric(12,2)` | ≈ 8 | variable |
| `status` | `varchar(20)` | ≈ 9 | variable: `CONFIRMED` y `COMPLETED` tienen 9 letras |

- Campos fijos: 112 + 40 + 4 = **156 bytes**
- Campos variables: 2, que cuestan 4 × 2 = **8 bytes** de prefijo
- Mapa de bits de nulos: 15 campos, ⌈15 / 8⌉ = **2 bytes**
- Tamaño estimado de los variables: 8 + 9 = **17 bytes**

**L = 8 + 156 + 2 + 17 = 183 bytes**

Al normalizar, `bookings` perdió `organization_id`, que salía del servicio, y ganó `currency_id`, la
moneda del precio pactado. Los dos son `uuid`, así que L no cambió.

### 3.2 Registros por bloque (FR) y páginas (BR)

`P = 2 + 4·FR + FR·L`, de donde `FR = ⌊(P − 2) / (4 + L)⌋`

FR = ⌊(8 192 − 2) / (4 + 183)⌋ = ⌊8 190 / 187⌋ = ⌊43,80⌋ = **43 registros por página**

`BR = ⌈TR / FR⌉`

BR = ⌈1 584 000 / 43⌉ = ⌈36 837,2⌉ = **36 838 páginas**

Espacio de la tabla = 36 838 × 8 192 bytes = 301 776 896 bytes ≈ **288 MB**

### 3.3 Índice `pk_bookings`

Elijo el índice de la clave primaria porque es el que usan todas las claves foráneas que apuntan a
una reserva, y porque cada reserva es un valor distinto: V(id, bookings) = TR. Hay uno más grande,
`uk_bookings_snapshot`, que sólo existe para la FK de `booking_resources` y cuya clave es más ancha.

**Entradas por nodo.** Cada entrada guarda la clave y un puntero a la tupla. Tomo 6 bytes para el
puntero, que es lo que mide un TID de PostgreSQL (bloque + posición).

- L del índice = 16 (`uuid`) + 6 (puntero) = 22 bytes
- FR = ⌊B / L⌋ = ⌊8 192 / 22⌋ = **372 entradas por nodo**

**Orden del árbol.** 2d − 1 = FR → 2d − 1 = 372 → d = 186,5 → **d = 186** (cumple d ≥ 3)

**Altura.** `H ≤ log_d V(a,R)`

log₁₈₆ 1 584 000 = ln 1 584 000 / ln 186 = 14,275 / 5,226 = 2,73

Un árbol no tiene niveles fraccionarios: 2 niveles no alcanzan para 1 584 000 valores, porque 186² =
34 596 se queda corto, y 3 sí. H = ⌈2,73⌉ = **3 niveles**, que es lo que da la tabla de nodos por nivel.

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

### 3.4 Lo que mide PostgreSQL

Con las 1 584 000 reservas cargadas en orden aleatorio, como llegarían en producción:

| Medida | Calculado | Medido | Diferencia |
|---|---|---|---|
| Páginas de `bookings` | 36 838 | 39 600 | +7,5 % |
| Registros por página | 43 | 40 | |
| Altura de `pk_bookings` | 3 | 3 (raíz en el nivel 2 de `bt_metap`) | igual |
| Páginas de `pk_bookings` | ≤ 8 564 | 8 393 | dentro de la cota |

La tabla mide un 7,5 % más porque PostgreSQL le pone a cada tupla una cabecera de 23 bytes y a cada
página una de 24, y la fórmula del curso no las cuenta. Con la fila real de 200 bytes que mide
`pg_column_size`, la misma fórmula da ⌊8 168 / 204⌋ = 40 registros por página, justo lo medido.

El índice queda cerca de la cota porque los `uuid` llegan en desorden y parten las páginas por la
mitad cada vez que se llenan, así que los nodos quedan llenos en promedio cerca del 70 %. Si las
reservas llegaran ordenadas por `id`, el índice se llenaría casi entero y mediría bastante menos.

## 4. Costo de una consulta con reunión

### 4.1 La consulta

*¿Cuántas reservas e ingresos dejó cada servicio de un proveedor en el mes?* Es la consulta 24 de
[`consultas.sql`](../consultas.sql), el reporte mensual que ve el dueño del negocio. Aquí la escribo
con el proveedor como parámetro y un mes fijo, que es como la corrí contra la base de volumen.

```sql
select s.name as servicio, count(*) as reservas, sum(b.total_price) as ingresos
from bookings b
    inner join services s on s.id = b.service_id
where s.organization_id = :proveedor
  and b.starts_at >= '2026-10-01' and b.starts_at < '2026-11-01'
  and b.status in ('CONFIRMED', 'COMPLETED')
group by s.name
order by ingresos desc;
```

### 4.2 Estadísticas y de dónde salen

**Páginas de `services` (BS)**, con el mismo método de la sección 3.1:

- Fijos: `id`, `organization_id` y `currency_id` (3 × 16 = 48), `duration_minutes`,
  `preparation_minutes`, `cleanup_minutes` y `customer_capacity` (4 × 4 = 16), `created_at` y
  `updated_at` (2 × 8 = 16): **80 bytes**
- Variables: `name` ≈ 20, `description` ≈ 60, `price` ≈ 8 y `status` ≈ 6: **94 bytes**, con un
  prefijo de 4 × 4 = **16 bytes**
- Mapa de bits: 13 campos, ⌈13 / 8⌉ = **2 bytes**
- L = 16 + 80 + 2 + 94 = **192 bytes** → FR = ⌊8 190 / 196⌋ = 41 → BS = ⌈5 440 / 41⌉ = **133 páginas**

| Estadística | Valor | De dónde sale |
|---|---|---|
| TR (bookings) | 1 584 000 | estimación de volumen del README |
| BR (bookings) | 36 838 | sección 3.2 |
| TS (services) | 5 440 | 680 proveedores × 8 servicios |
| BS (services) | 133 | arriba |
| V(organization_id, services) | 680 | un valor por proveedor |
| S(organization_id, services) | 5 440 / 680 = 8 | servicios de un proveedor |
| V(service_id, bookings) | 5 440 | todo servicio tiene reservas |
| S(service_id, bookings) | 1 584 000 / 5 440 = 291,2 ≈ 292 | reservas por servicio |
| Fracción del mes | 1/12 | reservas repartidas parejo en el año |
| Fracción de estados | 0,75 | supuesto: 60 % `COMPLETED` + 15 % `CONFIRMED` |
| HI de `uk_services_org_name` | 2 | entrada de 16 + 20 + 6 = 42 bytes → FR = 195, d = 98 → ⌈log₉₈ 5 440⌉ = ⌈1,88⌉ = 2 |
| HI de `ix_bookings_service_starts` | 3 | entrada de 16 + 8 + 6 = 30 bytes → FR = 273, d = 137 → ⌈log₁₃₇ 1 584 000⌉ = ⌈2,90⌉ = 3. Medido: 3 niveles |
| Reservas de un servicio en el mes | 292 × 1/12 = 24,3 ≈ 25 | S(service_id, bookings) por la fracción del mes |

En la base de volumen, `pg_stats` da n_distinct(bookings.service_id) = 5 437 y, para
`services.organization_id`, −0,125, que PostgreSQL usa para decir "una fracción de las filas":
0,125 × 5 440 = 680. Coinciden con los supuestos.

**Tamaño de la salida.** `service_id` referencia la clave de `services`, así que la reunión completa
devuelve TR = 1 584 000 tuplas. Con los filtros quedan
1 584 000 × (8 / 5 440) × (1/12) × 0,75 ≈ **146 tuplas**.

### 4.3 Alternativas de ejecución

**A. Reunión por ciclos anidados, sin índice ni filtros previos.** `services` va como relación externa
porque es la pequeña. Sus 133 páginas caben en las M − 2 = 510 páginas de memoria, así que `bookings`
se recorre una sola vez:

Costo = BS + BR × ⌈BS / (M − 2)⌉ = 133 + 36 838 × ⌈133 / 510⌉ = 133 + 36 838 × 1 = **36 971 páginas**

**B. Ciclos anidados con índice, filtrando primero los servicios.** La relación externa T son los
servicios del proveedor. Los saco con el índice secundario `uk_services_org_name`:

Costo de obtener T = HI + S(organization_id, services) = 2 + 8 = 10 páginas

Ese costo es el que cargo como BT. Las 8 tuplas caben en una página, pero producirlas cuesta 10
lecturas. Después, por cada servicio, busco sus reservas en el índice de `bookings`. Supongo el peor
caso: cada reserva en una página distinta, que es lo esperable porque las reservas de un servicio
llegan revueltas con las demás. Hay dos variantes, según el índice:

*B1. Con un índice sólo sobre `service_id`, el que tenía el equipo.* Cada búsqueda trae las 292
reservas del servicio y el filtro de fechas se aplica después, sobre las tuplas leídas. La fórmula de
referencia da:

Costo = BT + TT × S(service_id, bookings) = 10 + 8 × 292 = **2 346 páginas**

La fórmula no cuenta el descenso por el índice en cada búsqueda. Si lo sumo, cada búsqueda cuesta
HI + S = 3 + 292:

Costo = BT + TT × (HI + S) = 10 + 8 × (3 + 292) = **2 370 páginas**

*B2. Con el índice `(service_id, starts_at)` de este esquema.* Dentro de las entradas de cada servicio,
las fechas están ordenadas, así que la búsqueda es una selección por rango sobre el árbol B+. Con la
fórmula de referencia, la fracción del rango es c = 1/12 (un mes de doce) y cada búsqueda cuesta
HI + LB·c + S·c. Las entradas de un servicio caben en una hoja, así que LB·c es menos de una página y
lo redondeo a 0:

Costo por búsqueda = 3 + ⌈292 × 1/12⌉ = 3 + 25 = 28 páginas

Costo = BT + TT × 28 = 10 + 8 × 28 = **234 páginas**

En los dos casos el filtro de estado se aplica sobre las tuplas leídas.

**C. Reunión por hash.** La relación con la que se arma la tabla hash son los 8 servicios ya filtrados,
que ocupan una página y caben de sobra en las M − 2 páginas de memoria. Entonces es la variante en
memoria: se arma la tabla con T y se recorre `bookings` una vez.

Costo = BT + BR = 10 + 36 838 = **36 848 páginas**

Si la relación pequeña no cupiera en memoria haría falta el Grace hash join, que exige M > √BR
(512 > 192, se cumple) y cuesta 3 × (BR + BS) = 3 × (36 838 + 133) = 110 913 páginas.

**D. Ordenamiento y mezcla.** Con ⌈log₅₁₁ 36 838⌉ = 2 pasadas para `bookings` y ⌈log₅₁₁ 133⌉ = 1 para `services`:

Costo = BR + BS + 2·BR·2 + 2·BS·1 = 36 838 + 133 + 147 352 + 266 = **184 589 páginas**

### 4.4 Comparación

| Alternativa | Costo calculado (páginas) | Medido en PostgreSQL |
|---|---|---|
| A. Ciclos anidados | 36 971 | |
| B1. Ciclos anidados con índice sobre `service_id` | 2 370 | 2 339, con ese índice creado para medir |
| **B2. Ciclos anidados con índice `(service_id, starts_at)`** | **234** | **226**, el plan que elige el optimizador |
| C. Hash, en memoria | 36 848 | 39 613, forzado con `enable_nestloop = off` |
| D. Ordenamiento y mezcla | 184 589 | |

B2 es unas 160 veces más barata que A o C, y diez veces más barata que B1. A y C leen la tabla entera
para quedarse con 146 filas. B1 sólo lee las reservas de 8 servicios de 5 440, pero de todo el año.
B2 lee sólo las del mes. El `EXPLAIN (ANALYZE, BUFFERS)` de B2 lo confirma: 10 páginas de `services`,
25 del índice y 191 de `bookings`. La medición de C da más que el cálculo porque la tabla real tiene
39 600 páginas y no 36 838 (sección 3.4).

**Lo que cuesta el índice compuesto.** Mide 76 MB, frente a los 15 MB del de una sola columna. Como lo
reemplaza, cada reserva nueva sigue actualizando un solo índice por servicio. Pagar 61 MB por leer
diez veces menos en todos los reportes por servicio y fecha me parece un buen negocio, y por eso lo
dejé en el esquema.

## 5. Optimización algebraica

Uso la notación del curso. `bookings` y `services` comparten los nombres `id`, `currency_id`,
`status`, `created_at` y `updated_at`, y el producto cartesiano exige cabeceras sin nombres repetidos.
Por eso renombro `services` antes del producto:

```
S ← ρS(s_id, s_org, s_name, s_description, s_duration, s_preparation, s_cleanup,
       s_price, s_currency, s_capacity, s_status, s_created, s_updated)(services)
B ← bookings
```

Abrevio los predicados:

- p₁: `service_id = s_id`
- p₂: `s_org = X`
- p₃: `starts_at ≥ '2026-10-01' ∧ starts_at < '2026-11-01'`
- p₄: `status ∈ {CONFIRMED, COMPLETED}`

### 5.1 Expresión inicial

La traducción directa del SQL: el `from` es un producto, el `where` una restricción y el `group by`
un agrupamiento.

```
E₀ = s_name Ģ COUNT(*) AS reservas, SUM(total_price) AS ingresos ( σ p₁ ∧ p₂ ∧ p₃ ∧ p₄ (B × S) )
```

El producto B × S genera 1 584 000 × 5 440 = **8 616 960 000 tuplas** antes de filtrar nada.

### 5.2 Transformaciones

**Paso 1. Ley 2, selección conjunta.** Parto la restricción en una cascada para poder mover cada
parte por separado.

```
Ģ ( σ p₁ ( σ p₂ ( σ p₃ ∧ p₄ ( B × S ) ) ) )
```

**Paso 2. Leyes 4 y 5, selección sobre un producto.** p₂ sólo usa atributos de S, y p₃ ∧ p₄ sólo
atributos de B, así que cada una baja a su relación. p₁ usa las dos y se queda arriba.

```
Ģ ( σ p₁ ( σ p₃ ∧ p₄ (B) × σ p₂ (S) ) )
```

**Paso 3. Definición de reunión theta.** Una restricción sobre un producto es una reunión:
σ condición (R₁ × R₂) ≡ R₁ θ condición R₂.

```
Ģ ( σ p₃ ∧ p₄ (B)  θ p₁  σ p₂ (S) )
```

**Paso 4. Una proyección debajo del agrupamiento.** Este paso no es una de las leyes de la tabla de
referencia, que no tratan el agrupamiento. Se apoya en cómo está definido Ģ: el resultado sólo depende
de los atributos de agrupamiento (`s_name`) y de los que agrega (`total_price`), así que puedo
proyectar antes sin cambiar el resultado. Hay un cuidado: π elimina tuplas repetidas, y
dos reservas del mismo servicio con el mismo precio quedarían en una sola, con lo que `COUNT(*)` y
`SUM` darían mal. Para no perderlas conservo la clave `id` de la reserva.

```
Ģ ( π id, s_name, total_price ( σ p₃ ∧ p₄ (B)  θ p₁  σ p₂ (S) ) )
```

**Paso 5. Ley 9, proyección sobre una reunión.** La proyección se reparte entre los dos lados. Cada
lado tiene que conservar sus atributos de p₁ (`service_id` y `s_id`) para que la reunión se pueda
seguir haciendo. Arriba queda la proyección original, que descarta esos atributos al final.

```
Ģ ( π id, s_name, total_price ( π id, service_id, total_price ( σ p₃ ∧ p₄ (B) )  θ p₁  π s_id, s_name ( σ p₂ (S) ) ) )
```

**Paso 6. Leyes 3 y 8, la proyección baja de la restricción.** En el lado de B, p₃ ∧ p₄ usa
`starts_at` y `status`. Por la ley 3, una proyección que conserve esos atributos conmuta con la
restricción:

π id, service_id, total_price, starts_at, status (σ p₃ ∧ p₄ (B)) ≡ σ p₃ ∧ p₄ (π id, service_id, total_price, starts_at, status (B))

Y por la ley 8, proyectar primero sobre esos cinco atributos y después sobre tres es lo mismo que
proyectar directamente sobre los tres. Juntas:

π id, service_id, total_price (σ p₃ ∧ p₄ (B)) ≡ π id, service_id, total_price (σ p₃ ∧ p₄ (π id, service_id, total_price, starts_at, status (B)))

Lo mismo en el lado de S, conservando `s_org`. Con esto cada tupla deja atrás las columnas que no se
van a usar desde que se lee de la tabla.

**Paso 7. Ley 11, orden de la reunión.** Conmuto los operandos para que la relación pequeña quede a la
izquierda. Es la externa del ciclo anidado con índice de la sección 4.3.

### 5.3 Expresión optimizada

```
E₁ = s_name Ģ COUNT(*) AS reservas, SUM(total_price) AS ingresos (
       π id, s_name, total_price (
           π s_id, s_name ( σ s_org = X ( π s_id, s_name, s_org (S) ) )
           θ s_id = service_id
           π id, service_id, total_price ( σ p₃ ∧ p₄ ( π id, service_id, total_price, starts_at, status (B) ) ) ) )
```

El `order by` no es una operación del álgebra relacional, que trabaja con conjuntos. Se aplica al
final sobre las 8 filas del resultado.

### 5.4 Por qué es más barata

| Medida | E₀ | E₁ |
|---|---|---|
| Tuplas que salen de S hacia la reunión | 5 440 | 8 |
| Tuplas que salen de B hacia la reunión | 1 584 000 | 1 584 000 × (1/12) × 0,75 = 99 000 |
| Tamaño de cada tupla de B que sube | 183 bytes | 16 + 16 + 8 = 40 bytes |
| Tuplas que genera el producto o la reunión | 8 616 960 000 | 146 |
| Tuplas que llegan al agrupamiento | 146 | 146 |

El resultado es el mismo. E₀ arma más de ocho mil millones de combinaciones para quedarse con 146.
En E₁ los filtros actúan antes de la reunión, así que sólo se combinan los 8 servicios del proveedor
con las reservas del mes. Las proyecciones además reducen cada reserva de 183 a 40 bytes antes de
que suba por el árbol.

En la base de volumen, σ p₃ ∧ p₄ (B) da 101 225 tuplas y la reunión 151. Había estimado 99 000 y 146.

El plan que ejecuta PostgreSQL, el B2 de la sección 4.3, es la forma física de E₁. No materializa
σ p₃ ∧ p₄ (B) entera: usa el índice `(service_id, starts_at)` para aplicar p₃ dentro de la búsqueda de
cada uno de los 8 servicios, y p₄ al leer las tuplas. Es decir, hace la restricción antes de la
reunión, que es justo lo que pide la heurística.
