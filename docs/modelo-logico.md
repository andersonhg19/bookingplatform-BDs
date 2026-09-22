# Modelo lógico — análisis tabla por tabla

**Sprint 1 · Bases de Datos · CodeF@ctory 2026-II**

Complemento del [README](../README.md). Aquí está el detalle que no cabe en el documento principal:
las dependencias funcionales de cada relación, la forma normal que alcanza y por qué.

Marco de referencia: las definiciones del curso (decks de Francisco Moreno, `Pres08BDI` y `Pres09BDI`).

> **2FN** — todo atributo no clave depende **por completo** de la clave primaria.
> **3FN** — además, los atributos no clave son **mutuamente independientes**.
> **BCNF** — **todo determinante es clave candidata**.

---

## Resumen

| Forma normal alcanzada | Tablas |
|---|---|
| BCNF | 15 |
| 3FN | 3 |
| 2FN por decisión documentada | 1 (`booking_resources`) |

Las 19 tablas cumplen el mínimo de 3FN que pide la rúbrica. La excepción es `booking_resources`,
cuya violación de 2FN es deliberada, está justificada y está garantizada por el motor, no confiada
a la aplicación. Ver §5.

---

## 1. Catálogos

### `cities`

| Columna | Tipo | Clave | Notas |
|---|---|---|---|
| `id` | `uuid` | PK | |
| `name` | `varchar(120)` | UK con `region` | |
| `region` | `varchar(120)` | UK con `name` | Departamento |

Claves candidatas: `{id}` y `{name, region}`, ambas declaradas. No hay más determinantes.
`region` no determina `name` ni al revés. **BCNF.**

La razón de que `region` exista: en Colombia hay municipios homónimos en departamentos distintos, así
que `unique(name)` a secas sería una dependencia funcional falsa.

### `organization_categories`

Claves candidatas `{id}` y `{name}`. El único atributo no clave *es* la otra clave candidata. **BCNF.**

### `currencies`

| Columna | Tipo | Clave | Notas |
|---|---|---|---|
| `id` | `uuid` | PK | |
| `code` | `char(3)` | UK | ISO 4217, validado con `check (code ~ '^[A-Z]{3}$')` |
| `name` | `varchar(60)` | UK | |
| `active` | `boolean` | | La baja es lógica: hay servicios que la referencian |

Determinantes: `id`, `code` y `name`, los tres declarados como claves candidatas. **BCNF.**

`unique(name)` no es decorativo: sin él, `name → code` sería una dependencia funcional no respaldada
y la tabla caería a 3FN.

---

## 2. Identidad

### `clients` — Sprint 1, implementado

| Columna | Tipo | Clave | Notas |
|---|---|---|---|
| `id` | `uuid` | PK | `= auth.users.id` de Supabase |
| `full_name` | `varchar(120)` | | |
| `document` | `varchar(30)` | UK | |
| `birth_date` | `date` | | `check`: mayor de 18 años |
| `email` | `varchar(160)` | UK | Y único también en minúsculas |
| `phone` | `varchar(20)` | | `check` de formato |
| `city` | `varchar(80)` | | Texto libre (heredado) |
| `notification_channel` | `varchar(20)` | | `EMAIL` / `SMS` / `WHATSAPP` |
| `status` | `varchar(30)` | | `PENDING_VERIFICATION` / `ACTIVE` / `SUSPENDED` |
| `created_at`, `updated_at` | `timestamp(6)` | | Sin zona, por el mapeo JPA |

Tres claves candidatas declaradas: `{id}`, `{email}`, `{document}`. **BCNF.**

`city` es texto libre, pero como **no** se guarda el departamento, no arrastra la dependencia
`city → region` que la sacaría de 3FN. Es un problema de calidad de dominio (`'Medellín'` y
`'Medellin'` podrían convivir), no de normalización. `locations` sí usa el catálogo `cities`.

La tabla no se modifica: es trabajo entregado y en producción. Lo único que se le añadió son
restricciones, que Hibernate ignora al validar, y un índice único sobre `lower(email)`.

Ese índice es defensa en profundidad, no la corrección de un fallo. La aplicación ya normaliza el
correo a minúsculas antes de guardarlo y consulta con `IgnoreCase`, así que por la vía normal no
entran duplicados. Pero `uk_clients_email unique (email)` distingue mayúsculas, de modo que la
garantía depende de que la aplicación se acuerde de normalizar: una carga masiva, una migración o
un cliente nuevo podrían meter `Ana@x.com` junto a `ana@x.com`. Con el índice funcional, la
restricción deja de depender del código.

### `login_attempts` — Sprint 1, implementado

Relación de eventos. `id` determina todo y no hay ningún otro determinante. **BCNF.**

No se relaciona con `clients` a propósito: registra intentos con correos que pueden no corresponder a
ninguna cuenta, que es justamente lo que interesa vigilar.

---

## 3. Organización

### `organizations`

Claves candidatas `{id}` y `{nit}`. `category_id`, `status`, `approved_at`, `timezone` y los datos de
contacto son mutuamente independientes. **BCNF.**

`ck_organizations_approved` merece explicación: sólo `ACTIVE` y `SUSPENDED` pueden tener
`approved_at`, y `ACTIVE` la **exige**. No existe una organización activa sin registro de cuándo se
aprobó, que es la traza que pide HU-002.

### `organization_members`

Claves candidatas `{id}` y `{organization_id, user_id}`. `role` depende de la clave candidata
completa. **BCNF.**

Se conserva la clave primaria sustituta porque así la diseñó el equipo. La clave natural queda como
`unique`, lo que preserva igual la dependencia funcional: normalizar no exige que la clave natural
sea la primaria, exige que la dependencia esté garantizada.

### `organization_policies`

Claves candidatas `{id}`, `{organization_id, version}` y `{id, organization_id}` (clave alterna que
habilita las claves foráneas compuestas). Los tres parámetros de operación son mutuamente
independientes. **BCNF.**

Dos restricciones que valen la pena:

```sql
-- una sola política vigente por organización
create unique index ux_organization_policies_vigente
    on organization_policies (organization_id) where replaced_at is null;

-- y las versiones no se solapan en el tiempo, ni siquiera históricamente
constraint ex_organization_policies_solape exclude using gist (
    organization_id with =,
    tstzrange(effective_from, replaced_at) with &&
)
```

El índice único **parcial** es lo que permite tener N versiones históricas y exactamente una vigente.

### `locations`

Claves candidatas `{id}`, `{organization_id, name}`, `{id, organization_id}`. **BCNF.**

`timezone` es **nullable a propósito**: nulo significa "hereda la de la organización". Al ser un
override explícito y no un dato derivado de la ciudad, **no existe** la dependencia
`city_id → timezone` que sacaría la tabla de 3FN. Si `timezone` fuera obligatoria y siempre igual a
la de la ciudad, sí sería una dependencia transitiva y habría que mover la columna a `cities`.

---

## 4. Servicios y recursos

### `services`

Claves candidatas `{id}`, `{organization_id, name}`, `{id, organization_id}`. Duración, precio,
capacidad y tiempos de preparación son mutuamente independientes. **BCNF.**

`customer_capacity` codifica la regla de HU-004 sin una columna extra: `1` es individual, mayor que
`1` es grupal. El `check (customer_capacity >= 1)` cubre "un servicio grupal exige cupo mayor a 1"
por construcción.

### `service_locations`

Relación de intersección de la N:M servicio ↔ sede. PK compuesta `(service_id, location_id)`, que es
la conversión correcta según `Pres07BDI`. **BCNF** (todo-clave).

Lleva `organization_id` para que las claves foráneas compuestas impidan publicar un servicio de la
organización A en una sede de la B. Es redundancia, sí, pero **garantizada por el motor**: no puede
divergir porque las dos FK apuntan a claves alternas `(id, organization_id)`.

### `resource_types`, `service_resource_requirements`, `resources`

Las tres con clave sustituta más clave natural declarada como `unique`:
`(organization_id, name)`, `(service_id, resource_type_id)` y `(location_id, name)`. **BCNF.**

`resources.uk_resources_id_location` es la clave alterna que permite exigir, vía FK compuesta, que un
recurso asignado a una reserva **esté en la sede de esa reserva**.

### `schedules`

| Columna | Tipo | Notas |
|---|---|---|
| `id` | `uuid` | PK sustituta |
| `location_id` | `uuid` | FK |
| `resource_id` | `uuid` | FK; **nulo = toda la sede** |
| `day_of_week` | `smallint` | `check between 1 and 7` (ISO: 1 = lunes) |
| `start_time`, `end_time` | `time` | Horario de pared; la zona la aporta la sede |
| `active` | `boolean` | |

Clave candidata de negocio: `(location_id, resource_id, day_of_week, start_time, end_time)`,
declarada como `unique nulls not distinct`. **BCNF.**

El `nulls not distinct` (PostgreSQL 15+) es imprescindible: sin él, las franjas de sede completa
—las que tienen `resource_id` nulo— se podrían duplicar indefinidamente, porque `null = null` no es
verdadero. Una tabla sin clave de negocio admite el mismo hecho N veces, y eso infla el denominador
de cualquier reporte de ocupación.

`resource_id → location_id` sería una dependencia entre atributos no clave, pero está **garantizada**
por la FK compuesta contra `resources (id, location_id)`, así que no es una transitiva libre: el
esquema impide que difieran. Con `match simple`, si `resource_id` es nulo la FK no se verifica y las
franjas de sede completa siguen funcionando.

`time` sin zona es lo correcto: son horarios de pared ("abrimos a las 8"), no instantes absolutos.

---

## 5. Reservas

### `bookings`

Claves candidatas: `{id}` y la clave alterna `{id, starts_at, ends_at, status}`, que es el destino de
la clave foránea compuesta de `booking_resources`.

`currency_id` **se eliminó** de esta tabla. Era una dependencia transitiva —`id → service_id →
currency_id`— y además permitía registrar una reserva en euros de un servicio tarifado en pesos. La
moneda se lee por el servicio. **BCNF.**

`total_price` **no es una desnormalización**. Como `services.price` cambia con el tiempo, la
dependencia `service_id → total_price` **no se cumple** en esta relación: es el precio pactado, un
atributo semánticamente distinto del precio de catálogo.

`organization_id` sí es redundante —se deduce del servicio— pero es la única forma declarativa de
exigir que servicio, sede y política pertenezcan a la misma organización:

```sql
constraint fk_bookings_service_org  foreign key (service_id,  organization_id) references services              (id, organization_id),
constraint fk_bookings_location_org foreign key (location_id, organization_id) references locations             (id, organization_id),
constraint fk_bookings_policy_org   foreign key (policy_id,   organization_id) references organization_policies (id, organization_id),
constraint fk_bookings_service_location foreign key (service_id, location_id) references service_locations (service_id, location_id)
```

Sin ellas se podía reservar el servicio de la organización A, en la sede de B, bajo la política de C,
y ninguna consulta lo detectaba. Es redundancia mantenida por el motor, de la clase aceptable.

### `booking_resources` — la violación deliberada

| Columna | Tipo | Clave |
|---|---|---|
| `booking_id` | `uuid` | PK, FK compuesta |
| `resource_id` | `uuid` | PK, FK compuesta |
| `location_id` | `uuid` | FK compuesta con `resource_id` |
| `session_id` | `uuid` | |
| `starts_at`, `ends_at`, `status` | | **copia de `bookings`** |

`booking_id` es **parte** de la clave primaria y determina `starts_at`, `ends_at` y `status`. Eso es
una dependencia **parcial**: la tabla está en **1FN**, no llega a 2FN. Es el caso de libro de
`Pres09BDI`.

**Por qué es necesaria.** PostgreSQL no evalúa una restricción `EXCLUDE` a través de un join. Para
impedir que un recurso se reserve dos veces en franjas solapadas —el problema central del caso— el
rango tiene que estar en la misma tabla que `resource_id`. No hay alternativa declarativa.

**Por qué es aceptable.** Porque la copia **no puede divergir**:

```sql
constraint fk_booking_resources_bkg
    foreign key (booking_id, starts_at, ends_at, status)
    references bookings (id, starts_at, ends_at, status)
    on update cascade on delete cascade
```

La mantiene el motor. Verificado: mover una reserva tres horas arrastra la ocupación; cancelarla
propaga el estado y libera el recurso; intentar desincronizarlas a mano falla con violación de clave
foránea. Una redundancia **no garantizada** sería estrictamente peor que no tenerla —se paga el coste
sin obtener la garantía—; ésta sí lo está.

**La restricción anti-solapamiento:**

```sql
constraint ex_booking_resources_solape exclude using gist (
    resource_id with =,
    session_id  with <>,
    tstzrange(starts_at, ends_at) with &&
) where (status in ('RESERVED', 'CONFIRMED'))
```

El `session_id with <>` es lo que hace posibles los servicios grupales. Sin él, el segundo cliente
que reservara el mismo taller chocaba contra la restricción, porque comparte el salón con el primero:
el modelo declaraba cupos de 8 que su propia restricción prohibía usar. Con él, la regla se lee
*"un recurso no puede servir a dos **sesiones distintas** solapadas"*, que es la correcta.

`tstzrange` es `[)` por defecto, así que una reserva que termina a las 10:00 y otra que empieza a las
10:00 no se consideran solapadas. Es el comportamiento que se quiere.

### `booking_status_changes` y `account_status_changes`

Las dos con `id` como único determinante. **BCNF.**

`booking_status_changes` usa `on delete restrict`, no `cascade`: el historial de auditoría **no se
borra** con la reserva. Una traza que desaparece cuando se borra lo que traza no es una traza.

`account_status_changes` existe porque HU-003 pide motivo obligatorio al aprobar, suspender o
reactivar **cuentas**, no reservas, y `affected_bookings` congela el "informe de reservas afectadas"
que esa misma HU exige. Un trigger sobre `organizations` y `clients` impide cambiar el estado sin
dejar la fila correspondiente.

---

## 6. Reglas que no se pueden expresar de forma declarativa

PostgreSQL no admite subconsultas dentro de un `check`. Estas tres reglas comparan **entre tablas** y
por eso van en triggers, no en la aplicación: la garantía sigue viviendo en la base.

| Regla | HU | Dónde |
|---|---|---|
| Un proveedor no activo no es reservable | HU-002 | `fn_bookings_reglas` |
| Un cliente no verificado no confirma reservas | HU-001 | `fn_bookings_reglas` |
| Los asistentes de una sesión no superan el cupo del servicio | HU-004 | `fn_bookings_reglas` |
| Cambiar el estado de una cuenta exige registrar el motivo | HU-003 | `fn_exige_motivo_cuenta` |

Los límites que quedan fuera del modelo están declarados en el §7 del [README](../README.md).
