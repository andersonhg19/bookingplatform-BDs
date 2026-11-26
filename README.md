# Plataforma de Reservas de Servicios — Modelo de datos

Sprint 3 · Bases de Datos · CodeF@ctory 2026-II<br>
Anderson Herrera Guzmán · Facultad de Ingeniería, Universidad de Antioquia

Este repositorio tiene el modelo de datos del caso *Plataforma de Reservas de Servicios*. El backend
del equipo está en [`CodeFactoryBookingApp/bookingplatform`](https://github.com/CodeFactoryBookingApp/bookingplatform).

### Entregas por sprint

**La raíz del repositorio es la entrega del Sprint 3.** Las dos anteriores se conservan tal como se
presentaron, cada una en su carpeta y en su etiqueta de git, para poder compararlas.

| Sprint | Qué se calificó | Dónde está | Tablas |
|---|---|---|---|
| **3 (esta entrega)** | Triggers y procedimientos de las HU, MER y script refinados, consultas y roles actualizados | la raíz: [`README.md`](README.md), [`schema.sql`](schema.sql) | 35 |
| 2 | MER refinado, modelo físico completo en BCNF, consultas, volumen, roles y análisis de almacenamiento | [`sprint-2/`](sprint-2/) · etiqueta [`sprint-2`](https://github.com/andersonhg19/bookingplatform-BDs/tree/sprint-2) | 32 |
| 1 | Entidades y relaciones, preguntas clave, modelo lógico y modelo físico inicial | [`sprint-1/`](sprint-1/) · etiqueta [`sprint-1`](https://github.com/andersonhg19/bookingplatform-BDs/tree/sprint-1) | 19 |

Lo que cambió del Sprint 2 al 3 está en [Cambios respecto al Sprint 2](#cambios-respecto-al-sprint-2).
Dentro de `schema.sql` lo nuevo dice `[S3]`, y en las tablas del README, **[S3 nueva]** o *Sprint 3*.

### Archivos de esta entrega

| Archivo | Qué es |
|---|---|
| [`schema.sql`](schema.sql) | Modelo físico completo: 35 tablas en BCNF, restricciones, índices, 44 triggers, procedimientos, roles y RLS |
| [`seed.sql`](seed.sql) | Datos de prueba, pensados para que todas las consultas devuelvan filas. Las reservas del Sprint 3 se hacen con los procedimientos |
| [`consultas.sql`](consultas.sql) | Las 33 preguntas clave: 14 del Sprint 1, 10 del Sprint 2 y 9 del Sprint 3 |
| [`pruebas-sprint3.sql`](pruebas-sprint3.sql) | Cada trigger, procedimiento y permiso nuevo, en acción |
| [`pruebas-integridad.sql`](pruebas-integridad.sql) | Las 51 violaciones de datos y de permisos del Sprint 2, que la base sigue rechazando |
| [`docs/analisis-almacenamiento.md`](docs/analisis-almacenamiento.md) | Almacenamiento, índices, costo de una consulta y su optimización (Sprint 2) |
| [`docs/generar-volumen.sql`](docs/generar-volumen.sql) | Carga 1,58 millones de reservas para comprobar el análisis |
| [`docker-compose.yml`](docker-compose.yml) | PostgreSQL 16 y pgAdmin con todo cargado |

**Contenido:** [Cambios respecto al Sprint 2](#cambios-respecto-al-sprint-2) ·
[MER](#1-mer-refinado) · [Modelo físico](#2-modelo-físico) · [Normalización](#normalización) ·
[schema.sql](#3-schemasql) · [Triggers](#4-triggers) · [Procedimientos](#5-procedimientos-y-funciones) ·
[Consultas](#6-consultas) · [Volumen](#7-estimación-de-volumen) · [Seguridad](#8-roles-y-seguridad) ·
[Análisis](#9-análisis-de-almacenamiento-costo-y-optimización) · [Rúbrica](#dónde-está-cada-criterio-de-la-rúbrica)

## Cómo probarlo

```bash
docker compose up -d
```

Levanta PostgreSQL 16 en `localhost:5432` con `schema.sql` y `seed.sql` ya cargados, y pgAdmin en
<http://localhost:8080>. Las credenciales del `docker-compose.yml` son de desarrollo local. El
contenedor sólo queda `healthy` si existen las 35 tablas.

```bash
docker compose cp consultas.sql postgres:/tmp/
docker compose cp pruebas-sprint3.sql postgres:/tmp/
docker compose cp pruebas-integridad.sql postgres:/tmp/
docker compose exec postgres psql -U postgres -d reservas -f /tmp/consultas.sql
docker compose exec postgres psql -U postgres -d reservas -f /tmp/pruebas-sprint3.sql
docker compose exec postgres psql -U postgres -d reservas -f /tmp/pruebas-integridad.sql
```

Los dos archivos de pruebas deshacen lo que hacen, así que se pueden correr en cualquier orden y
cuantas veces se quiera.

Para empezar de cero: `docker compose down -v && docker compose up -d`.

## Cambios respecto al Sprint 2

El Sprint 3 es el del ciclo de vida de una reserva: crearla, confirmarla, cancelarla, reprogramarla,
cerrarla con la asistencia, avisarle al cliente y mostrarle su historial. El equipo implementó esas
historias entre el 21 y el 23 de noviembre, y para eso agregó al backend las migraciones V10 a V18.
Partí de ahí. La evolución del modelo es pequeña a propósito: tres tablas, cinco columnas, siete
triggers y nueve rutinas, y cada una responde a una HU. Lo que cambió del Sprint 1 al 2 está en el
[README del Sprint 2](sprint-2/README.md#qué-cambió-frente-al-sprint-1).

**1. En el MER.**

| Cambio | HU | Por qué |
|---|---|---|
| `bookings.code` (V11 del equipo) | 018 | El cliente busca su reserva con un código que puede dictar por teléfono, como `RSV-1A2B-3C4D-5E6F`, y no con un `uuid`. Es una segunda clave candidata, así que `bookings` sigue en BCNF. Conserva el `varchar(64)` de V11; el `CHECK` fija el formato |
| `organization_policies`: `manual_confirmation`, `max_reschedules`, `default_closure_status` y `auto_close_delay_hours` (V14, V17 y V18) | 012, 014, 016 | Son reglas del proveedor que cambian con el tiempo. Van en la política versionada y no en `organizations`, para que cada reserva se rija por las que había cuando se hizo |
| Nueva **`booking_reschedules`** | 014 | Cada reprogramación: de qué sesión a cuál, quién la hizo y por qué. Antes, al mover una reserva se perdía de dónde venía |
| Nueva **`organization_booking_reminders`** | 015 | Con cuánta anticipación recuerda cada proveedor la cita: un recordatorio por fila |
| Nueva **`booking_notices`** | 015 | La cola de avisos de cada reserva. La llena un trigger y la vacía el backend al enviar |

Hubo cosas del equipo que no copié tal cual, y lo explico:

- **`reschedule_count` (V17).** Es un contador de las reprogramaciones, y ese dato se obtiene con un
  `count(*)` sobre `booking_reschedules`. Guardarlo sería repetir algo calculable, y el contador podría
  decir 1 mientras la historia tiene 2.
- **`late_reschedule` (V17) y `late_cancellation` (V15).** Dicen si el cambio fue tardío, y eso se
  deduce de la hora del cambio, el inicio de la cita y la ventana gratis de la política que congeló la
  reserva, que ya están guardados. `sp_cancelar_reserva` lo devuelve al cancelar y las consultas 26 y 27
  lo calculan.
- **`audit_events` (V10 y V13).** La auditoría ya la cubre `audit_log` desde el Sprint 2, con una fila por
  columna que cambia (HU-023).
- **`platform_role_changes` (V10) y `booking_notification_preferences` (V12).** La primera es de la
  gestión de roles (HU-022) y queda fuera de este sprint. El canal que el cliente prefiere ya lo guarda
  `clients.notification_channel`.

**2. En el script.**

- Ocho triggers nuevos: siete sobre la reserva y la auditoría de los recordatorios. Además,
  `tg_sessions_coherencia` ya no deja mover una sesión que tenga reservas (HU-014). Están en
  [Triggers](#4-triggers), con su evento, su momento y su HU.
- Cinco procedimientos y cuatro funciones de consulta, que están en
  [Procedimientos y funciones](#5-procedimientos-y-funciones). Crear y reprogramar una reserva por
  procedimiento revisa que la hora sea una franja de la agenda y asigna los recursos que el servicio
  exige. En el Sprint 2 eso aparecía en la lista de lo que el esquema no garantizaba.
- Índices nuevos para lo que estas HU consultan: las reservas vivas, los avisos pendientes y las
  reprogramaciones de una reserva.
- El `seed.sql` crea, reprograma, cancela y cierra reservas llamando a los procedimientos, como lo
  haría el backend.
- El nuevo [`pruebas-sprint3.sql`](pruebas-sprint3.sql) tiene una prueba por cada trigger, cada
  procedimiento y cada permiso nuevo. En [`pruebas-integridad.sql`](pruebas-integridad.sql) cambiaron
  cuatro pruebas que dependían de una sesión que ahora se reprograma en el seed, y las 51 siguen fallando
  con el mismo mensaje del Sprint 2.

**3. En las consultas.** Hay nueve nuevas, de la 25 a la 33, y cada una responde a una o dos HU del
sprint. Las 24
anteriores corren sin cambios sobre el esquema refinado: lo nuevo se agregó y ninguna columna que usaban
cambió.

**4. En los roles.** PostgreSQL le da `EXECUTE` a todo el mundo (`PUBLIC`) sobre cada función que se crea.
Ahora se le quita a todas las rutinas propias, y cada rol recibe sólo las que usa. `rol_app` tiene
permisos sobre las tres tablas nuevas, pero no puede escribir en la cola de avisos ni editar el código de
una reserva. Además, ahora inserta en `bookings` sólo las columnas que pide el cliente y sólo puede
cambiarle la sesión y el estado: las fechas las pone la base, porque de ellas salen la anticipación y la
cancelación tardía, y los asistentes no cambian, porque el precio se pactó por persona. `rol_lectura` puede ejecutar
las dos funciones que no muestran datos personales. En Supabase, un cliente ve las reprogramaciones y los
avisos de sus propias reservas. Está en [Roles y seguridad](#8-roles-y-seguridad).

Igual que en el Sprint 2, **no toqué el repositorio del equipo**. Esto es una propuesta para la base:
que el backend use los procedimientos sería una migración nueva de ellos (V19 en adelante).

## 1. MER refinado

Son 35 tablas, así que primero va un mapa por dominios y después tres vistas de entidad-relación con
las claves, los atributos principales y las cardinalidades. En las vistas de detalle, las tablas nuevas
dicen **S3 nueva** o **S2 nueva** en su clave primaria, las que normalicé en el Sprint 2 dicen
**S2 normalizada**, y cada columna que se agregó en el Sprint 3 dice **S3**.

`auth.users` la gestiona Supabase Auth y no se crea aquí. Por eso `clients.id`,
`organization_members.user_id` y los `changed_by` no tienen clave foránea declarada.

### Vista general

Los ocho dominios del modelo y de qué depende cada uno. **★** marca una tabla nueva o cambiada en el Sprint 3, **✚** una tabla nueva del Sprint 2 y **✱** una que normalicé en el Sprint 2. Las relaciones tabla por tabla, con sus cardinalidades, están en las tres vistas de abajo.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 320}}}%%
flowchart LR
    CAT["<b>Catálogos</b><br/>cities<br/>organization_categories<br/>currencies"]
    IDE["<b>Identidad</b><br/>clients ✱<br/>client_status_changes ✱<br/>login_attempts ✱"]
    ORG["<b>Organización</b><br/>organizations<br/>organization_members ✱<br/>organization_policies ★<br/>organization_status_changes ✱<br/>locations"]
    SER["<b>Servicios y recursos</b><br/>services<br/>service_locations ✱<br/>resource_types<br/>service_resource_requirements ✱<br/>resources ✱<br/>resource_maintenances"]
    AGE["<b>Agendas</b><br/>agendas ✱<br/>agenda_services ✱<br/>schedules<br/>agenda_exceptions ✚"]
    RES["<b>Reservas y pagos</b><br/>sessions ✚<br/>bookings ✱ ★<br/>session_resources ✚<br/>booking_status_changes<br/>booking_reschedules ★<br/>booking_reviews ✚<br/>waitlist_entries ✚<br/>payments ✚"]
    REP["<b>Reportes</b><br/>resource_occupancy_daily ✚"]
    AUD["<b>Notificaciones y auditoría</b><br/>sent_emails<br/>organization_booking_reminders ★<br/>booking_notices ★<br/>audit_log ✚<br/>audit_log_changes ✚"]

    CAT -->|ciudad, categoría| ORG
    CAT -->|ciudad| IDE
    CAT -->|moneda| SER
    ORG -->|proveedor y sede| SER
    SER -->|sede y recurso| AGE
    SER -->|servicio en sede, recurso| RES
    IDE -->|cliente| RES
    ORG -->|política| RES
    CAT -->|moneda| RES
    SER -->|recurso| REP
    RES -->|avisos| AUD
    ORG -->|recordatorios| AUD
    RES -. registra .-> AUD
    ORG -. registra .-> AUD
    IDE -. registra .-> AUD

    classDef dominio fill:#f8f9fa,stroke:#495057,color:#212529,text-align:left
    class CAT,IDE,ORG,SER,AGE,RES,REP,AUD dominio
```

### Identidad y organización

```mermaid
erDiagram
    cities ||--o{ clients : "vive en"
    cities ||--o{ locations : ubica
    clients ||--o{ client_status_changes : "cambia de estado"
    organization_categories ||--o{ organizations : clasifica
    organizations ||--o{ organization_members : "tiene personal"
    organizations ||--o{ organization_policies : "versiona sus reglas"
    organizations ||--o{ locations : "tiene sedes"
    organizations ||--o{ organization_status_changes : "cambia de estado"

    cities {
        uuid id PK
        varchar name UK "único con region"
        varchar region UK
    }
    organization_categories {
        uuid id PK
        varchar name UK
    }
    clients {
        uuid id PK "S2 normalizada; = auth.users.id"
        uuid city_id FK
        varchar document UK
        varchar email UK
        varchar full_name
        date birth_date "mayor de 18"
        varchar status "PENDING_VERIFICATION, ACTIVE, SUSPENDED"
    }
    client_status_changes {
        uuid id PK "S2 normalizada"
        uuid client_id FK
        varchar from_status
        varchar to_status
        varchar reason "obligatorio"
    }
    login_attempts {
        bigint id PK
        varchar email "no es FK: también correos inexistentes"
        boolean success
        timestamptz attempted_at
    }
    organizations {
        uuid id PK
        uuid category_id FK
        varchar identification_type UK "NIT, CC, CE, PASAPORTE"
        varchar identification_number UK
        varchar name
        varchar status "PENDING_APPROVAL, ACTIVE, SUSPENDED, REJECTED"
        timestamptz approved_at
    }
    organization_members {
        uuid organization_id PK, FK "S2 normalizada"
        uuid user_id PK
        varchar role "OWNER, MANAGER, STAFF"
    }
    organization_policies {
        uuid id PK
        uuid organization_id FK
        int version UK "único con organization_id"
        int booking_notice_minutes_min
        int booking_notice_minutes_max
        int free_cancellation_window_minutes
        boolean manual_confirmation "S3: HU-012"
        int max_reschedules "S3: HU-014"
        varchar default_closure_status "S3: HU-016"
        int auto_close_delay_hours "S3: HU-016"
        timestamptz effective_from
        timestamptz replaced_at "nulo = vigente"
    }
    locations {
        uuid id PK
        uuid organization_id FK
        uuid city_id FK
        varchar name UK "único por proveedor"
        varchar timezone "nulo = la del proveedor"
        varchar status "ACTIVE, INACTIVE"
    }
    organization_status_changes {
        uuid id PK "S2 normalizada"
        uuid organization_id FK
        varchar from_status
        varchar to_status
        varchar reason "obligatorio"
        int affected_bookings
    }
```

### Servicios, recursos y agendas

```mermaid
erDiagram
    organizations ||--o{ services : ofrece
    organizations ||--o{ resource_types : define
    currencies ||--o{ services : "cobra en"
    services ||--o{ service_locations : "se presta en"
    locations ||--o{ service_locations : presta
    services ||--o{ service_resource_requirements : exige
    resource_types ||--o{ service_resource_requirements : "es exigido"
    resource_types ||--o{ resources : "tiene instancias"
    locations ||--o{ resources : aloja
    resources ||--o{ resource_maintenances : "entra a mantenimiento"
    resources ||--o{ resource_occupancy_daily : "se mide"
    locations |o--o{ agendas : "agenda de toda la sede"
    resources |o--o{ agendas : "agenda propia del recurso"
    agendas ||--o{ agenda_services : habilita
    services ||--o{ agenda_services : "es reservable en"
    agendas ||--o{ schedules : "tiene bloques"
    agendas ||--o{ agenda_exceptions : "tiene excepciones"

    organizations {
        uuid id PK
    }
    locations {
        uuid id PK
        uuid organization_id FK
    }
    currencies {
        uuid id PK
        char code UK "ISO 4217"
        varchar name UK
        boolean active
    }
    services {
        uuid id PK
        uuid organization_id FK
        uuid currency_id FK
        varchar name UK "único por proveedor"
        int duration_minutes
        numeric price
        int customer_capacity "1 individual, mayor que 1 grupal"
        varchar status "nace INACTIVE"
    }
    service_locations {
        uuid service_id PK, FK "S2 normalizada"
        uuid location_id PK, FK
    }
    resource_types {
        uuid id PK
        uuid organization_id FK
        varchar name UK "único por proveedor"
    }
    service_resource_requirements {
        uuid service_id PK, FK "S2 normalizada"
        uuid resource_type_id PK, FK
        int quantity_required
    }
    resources {
        uuid id PK "S2 normalizada"
        uuid resource_type_id FK
        uuid location_id FK
        varchar name UK "único por sede"
        int capacity
        varchar status "ACTIVE, RETIRED"
    }
    resource_maintenances {
        uuid id PK
        uuid resource_id FK
        timestamptz starts_at "no se solapan"
        timestamptz ends_at
        varchar reason
    }
    agendas {
        uuid id PK "S2 normalizada"
        uuid location_id FK "de la sede, o"
        uuid resource_id FK "del recurso, nunca los dos"
        varchar name UK "única por dueño"
        smallint slot_minutes "15, 30 o 60"
        date valid_from
        date valid_until "nulo = sin fin"
    }
    agenda_services {
        uuid agenda_id PK, FK "S2 normalizada"
        uuid service_id PK, FK
    }
    schedules {
        uuid id PK
        uuid agenda_id FK
        smallint day_of_week "1 lunes a 7 domingo"
        time start_time "no se solapan"
        time end_time
        boolean active
    }
    agenda_exceptions {
        uuid id PK "S2 nueva"
        uuid agenda_id FK
        date exception_date
        time start_time "nulo = todo el día"
        time end_time
        varchar reason
    }
    resource_occupancy_daily {
        uuid resource_id PK, FK "S2 nueva"
        date occupancy_date PK
        int available_minutes
        int booked_minutes
        int sessions_count
    }
```

### Reservas, pagos y auditoría

```mermaid
erDiagram
    service_locations ||--o{ sessions : "se agenda en"
    sessions ||--o{ bookings : "tiene reservas"
    clients ||--o{ bookings : reserva
    organization_policies ||--o{ bookings : "fija las condiciones de"
    currencies ||--o{ bookings : "precio en"
    sessions ||--o{ session_resources : ocupa
    resources ||--o{ session_resources : "es ocupado"
    bookings ||--o{ booking_status_changes : "cambia de estado"
    bookings ||--o| booking_reviews : "se califica"
    clients ||--o{ waitlist_entries : espera
    service_locations ||--o{ waitlist_entries : "tiene espera"
    bookings |o--o| waitlist_entries : "sale de"
    bookings ||--o{ payments : "se paga con"
    currencies ||--o{ payments : "cobrado en"
    bookings ||--o{ booking_reschedules : "se reprograma"
    sessions ||--o{ booking_reschedules : "sale de"
    sessions ||--o{ booking_reschedules : "llega a"
    bookings ||--o{ booking_notices : "avisa con"
    organizations ||--o{ organization_booking_reminders : "programa"

    clients {
        uuid id PK
    }
    service_locations {
        uuid service_id PK, FK
        uuid location_id PK, FK
    }
    organization_policies {
        uuid id PK
    }
    currencies {
        uuid id PK
    }
    resources {
        uuid id PK
    }
    organizations {
        uuid id PK
    }
    sessions {
        uuid id PK "S2 nueva"
        uuid service_id FK "con location_id, FK a service_locations"
        uuid location_id FK
        timestamptz starts_at
        timestamptz ends_at "fin pactado"
    }
    bookings {
        uuid id PK "S2 normalizada"
        varchar code UK "S3: HU-018"
        uuid client_id FK
        uuid session_id FK "servicio, sede y hora"
        uuid policy_id FK "congela las condiciones"
        uuid currency_id FK "moneda del precio pactado"
        int attendees
        numeric total_price "precio pactado"
        varchar status "RESERVED, CONFIRMED, CANCELLED, COMPLETED, NO_SHOW"
    }
    session_resources {
        uuid session_id PK, FK "S2 nueva"
        uuid resource_id PK, FK "sin choques de horario"
    }
    booking_status_changes {
        uuid id PK
        uuid booking_id FK
        varchar from_status
        varchar to_status
        varchar reason "obligatorio al cancelar"
    }
    booking_reschedules {
        uuid id PK "S3 nueva"
        uuid booking_id FK
        uuid from_session_id FK "de dónde venía"
        uuid to_session_id FK "a dónde pasó"
        varchar reason
        uuid rescheduled_by
        timestamptz rescheduled_at
    }
    organization_booking_reminders {
        uuid organization_id PK, FK "S3 nueva"
        int minutes_before PK "15 a 10080"
    }
    booking_notices {
        uuid id PK "S3 nueva"
        uuid booking_id FK
        varchar kind "CREATED, CONFIRMED, CANCELLED, RESCHEDULED, REMINDER"
        timestamptz due_at "cuándo sale"
        timestamptz processed_at "nulo = pendiente"
    }
    booking_reviews {
        uuid id PK "S2 nueva"
        uuid booking_id FK, UK "una por reserva"
        smallint rating "1 a 5"
        varchar comment
    }
    waitlist_entries {
        uuid id PK "S2 nueva"
        uuid client_id FK
        uuid service_id FK
        uuid location_id FK
        date desired_date
        int attendees
        varchar status "WAITING, NOTIFIED, BOOKED, EXPIRED, CANCELLED"
        uuid booking_id FK, UK "sólo si BOOKED"
        timestamptz notified_at
    }
    payments {
        uuid id PK "S2 nueva"
        uuid booking_id FK
        uuid currency_id FK
        numeric amount
        varchar method "CARD, BANK_TRANSFER, CASH"
        varchar status "PENDING, PAID, FAILED, REFUNDED"
        varchar external_reference UK
        timestamptz paid_at
        timestamptz refunded_at
    }
    sent_emails {
        uuid id PK
        varchar recipient
        varchar subject
        text body
        timestamptz sent_at
    }
    audit_log {
        bigint id PK "S2 nueva"
        varchar table_name
        varchar operation "INSERT, UPDATE, DELETE"
        text record_id
        varchar db_user
        uuid app_user_id
        timestamptz changed_at
    }
    audit_log_changes {
        bigint audit_log_id PK, FK "S2 nueva"
        varchar column_name PK
        text old_value
        text new_value
    }
    audit_log ||--o{ audit_log_changes : "detalla"
```

`booking_reschedules` llega dos veces a `sessions`: una por la sesión de la que salió la reserva y otra
por la sesión a la que llegó. Son dos relaciones distintas, cada una con su FK.

`sent_emails` y `audit_log` no tienen claves foráneas hacia el negocio a propósito. Un correo puede ir
a una dirección que no es de ningún cliente, y una fila de auditoría tiene que sobrevivir al registro
que describe.

## 2. Modelo físico

Esta sección la generé desde el catálogo de PostgreSQL después de correr `schema.sql`, así que
corresponde a lo que crea el script. Sólo le quité los casts que PostgreSQL agrega al reescribir las
restricciones (`::text`, `= ANY (ARRAY[...])`) para que se lean como en el `schema.sql`. Cada tabla
trae sus columnas con tipo, nulo, default y clave, con la acción `on delete` de cada FK cuando no
es la de omisión (`no action`). Debajo van las restricciones que abarcan varias columnas, los
`CHECK`, los `EXCLUDE` y los índices `ix_` que no salen de una restricción.

Debajo de cada tabla también van los triggers que aplican sus reglas, porque varias de ellas
reemplazan a restricciones declarativas (ver [Normalización](#normalización)). No repito en cada
tabla los dos triggers genéricos: `fn_set_updated_at`, que mantiene `updated_at`, y `fn_auditar`, que
escribe en `audit_log` los cambios de `clients`, `organizations`, `organization_members`,
`organization_policies`, `organization_booking_reminders`, `services`, `payments` y `booking_reviews`.
Las tablas y columnas del Sprint 3 dicen **[S3 nueva]** o *Sprint 3*, y sus triggers, **[S3]**.

Todas las restricciones e índices siguen el mismo patrón: `pk_`, `fk_`, `uk_`, `ck_`, `ex_`
(exclusión), `ix_` y `ux_` (índice único), seguidos del nombre de la tabla y de lo que controlan. Los
triggers empiezan por `tg_` y sus funciones por `fn_`; los procedimientos, por `sp_`, y las funciones
auxiliares, por `f_` (ver [Procedimientos y funciones](#5-procedimientos-y-funciones)).

<details>
<summary><b>Catálogos</b> · cities, organization_categories, currencies</summary>


#### `cities`

Catálogo de ciudades, con departamento.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `name` | `varchar(120)` | no |  |  |
| `region` | `varchar(120)` | no |  |  |

- UNIQUE `uk_cities_name_region`: `UNIQUE (name, region)`
- CHECK `ck_cities_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_cities_region`: `CHECK ((length(btrim(region)) > 0))`


#### `organization_categories`

Catálogo de categorías de negocio.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `name` | `varchar(80)` | no |  | UNIQUE |

- CHECK `ck_organization_categories_name`: `CHECK ((length(btrim(name)) > 0))`


#### `currencies`

Monedas ISO 4217. La baja es lógica (active).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `code` | `char(3)` | no |  | UNIQUE |
| `name` | `varchar(60)` | no |  | UNIQUE |
| `active` | `boolean` | no | `true` |  |

- CHECK `ck_currencies_code`: `CHECK ((code ~ '^[A-Z]{3}$'))`

</details>

<details>
<summary><b>Identidad</b> · clients, client_status_changes, login_attempts</summary>


#### `clients`

Perfil del cliente (HU-001); id = auth.users.id de Supabase.

*Sprint 2: normalizada: `city` pasa a `city_id`, fechas con zona, mayoría de edad por trigger.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no |  | PK |
| `full_name` | `varchar(120)` | no |  |  |
| `document` | `varchar(30)` | no |  | UNIQUE |
| `birth_date` | `date` | no |  |  |
| `email` | `varchar(160)` | no |  | UNIQUE |
| `phone` | `varchar(20)` | no |  |  |
| `city_id` | `uuid` | no |  | FK → `cities` (restrict) |
| `notification_channel` | `varchar(20)` | no |  |  |
| `status` | `varchar(30)` | no | `'PENDING_VERIFICATION'` |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_clients_document`: `CHECK ((length(btrim(document)) > 0))`
- CHECK `ck_clients_email`: `CHECK ((email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'))`
- CHECK `ck_clients_full_name`: `CHECK ((length(btrim(full_name)) > 0))`
- CHECK `ck_clients_notification_channel`: `CHECK ((notification_channel IN ('EMAIL', 'SMS', 'WHATSAPP')))`
- CHECK `ck_clients_phone`: `CHECK ((phone ~ '^\+?[0-9]{7,15}$'))`
- CHECK `ck_clients_status`: `CHECK ((status IN ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')))`
- UNIQUE (índice) `ux_clients_email_lower`: `USING btree (lower(email))`
- Índice `ix_clients_city`: `USING btree (city_id)`
- Trigger `tg_clients_mayor_de_edad`: HU-001: el cliente tiene al menos 18 años al registrarse


#### `client_status_changes`

Historia de estados de un cliente, con motivo obligatorio (HU-003).

*Sprint 2: normalizada: sale de `account_status_changes`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `client_id` | `uuid` | no |  | FK → `clients` (restrict) |
| `from_status` | `varchar(30)` | sí |  |  |
| `to_status` | `varchar(30)` | no |  |  |
| `reason` | `varchar(500)` | no |  |  |
| `changed_by` | `uuid` | sí |  |  |
| `changed_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_client_status_changes_from`: `CHECK (((from_status IS NULL) OR (from_status IN ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED'))))`
- CHECK `ck_client_status_changes_reason`: `CHECK ((length(btrim(reason)) > 0))`
- CHECK `ck_client_status_changes_to`: `CHECK ((to_status IN ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')))`
- Índice `ix_client_status_changes_client`: `USING btree (client_id, changed_at DESC)`


#### `login_attempts`

Intentos de ingreso para el bloqueo por cuenta (HU-021).

*Sprint 2: fecha con zona horaria.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `bigint` | no | `generated by default as identity` | PK |
| `email` | `varchar(160)` | no |  |  |
| `success` | `boolean` | no |  |  |
| `attempted_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_login_attempts_email`: `CHECK ((length(btrim(email)) > 0))`
- Índice `ix_login_attempts_email_lower`: `USING btree (lower(email), attempted_at)`

</details>

<details>
<summary><b>Organización</b> · organizations, organization_members, organization_policies, locations, organization_status_changes</summary>


#### `organizations`

Negocio proveedor (HU-002). PENDING_APPROVAL hasta que un administrador lo apruebe.

*Sprint 2: V4 del equipo: tipo y número de identificación.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `category_id` | `uuid` | no |  | FK → `organization_categories` (restrict) |
| `name` | `varchar(160)` | no |  |  |
| `identification_type` | `varchar(20)` | no | `'NIT'` |  |
| `identification_number` | `varchar(20)` | no |  |  |
| `contact_email` | `varchar(160)` | no |  |  |
| `contact_phone` | `varchar(20)` | no |  |  |
| `timezone` | `varchar(60)` | no | `'America/Bogota'` |  |
| `status` | `varchar(30)` | no | `'PENDING_APPROVAL'` |  |
| `approved_at` | `timestamptz` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- UNIQUE `uk_organizations_identification`: `UNIQUE (identification_type, identification_number)`
- CHECK `ck_organizations_approved`: `CHECK ((((status = 'ACTIVE') AND (approved_at IS NOT NULL)) OR ((status IN ('PENDING_APPROVAL', 'REJECTED')) AND (approved_at IS NULL)) OR (status = 'SUSPENDED')))`
- CHECK `ck_organizations_email`: `CHECK ((contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'))`
- CHECK `ck_organizations_identification_number`: `CHECK ((length(btrim(identification_number)) > 0))`
- CHECK `ck_organizations_identification_type`: `CHECK ((identification_type IN ('NIT', 'CC', 'CE', 'PASAPORTE')))`
- CHECK `ck_organizations_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_organizations_phone`: `CHECK ((contact_phone ~ '^\+?[0-9]{7,15}$'))`
- CHECK `ck_organizations_status`: `CHECK ((status IN ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')))`
- Índice `ix_organizations_status`: `USING btree (status)`
- Trigger `tg_organizations_motivo`: HU-003: cambiar el estado de un proveedor exige el motivo en organization_status_changes


#### `organization_members`

Quién trabaja en qué proveedor y con qué rol (ADR-0008).

*Sprint 2: normalizada: PK natural `(organization_id, user_id)`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `organization_id` | `uuid` | no |  | PK, FK → `organizations` (cascade) |
| `user_id` | `uuid` | no |  | PK |
| `role` | `varchar(30)` | no |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- PK `pk_organization_members`: `PRIMARY KEY (organization_id, user_id)`
- CHECK `ck_organization_members_role`: `CHECK ((role IN ('OWNER', 'MANAGER', 'STAFF')))`
- Índice `ix_organization_members_user`: `USING btree (user_id)`


#### `organization_policies`

Reglas de anticipación y cancelación, versionadas (HU-002).

*Sprint 3: `manual_confirmation`, `max_reschedules`, `default_closure_status` y `auto_close_delay_hours` (HU-012, HU-014 y HU-016; V14, V17 y V18 del equipo).*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `organization_id` | `uuid` | no |  | FK → `organizations` (restrict) |
| `version` | `integer` | no |  |  |
| `booking_notice_minutes_min` | `integer` | no |  |  |
| `booking_notice_minutes_max` | `integer` | no |  |  |
| `free_cancellation_window_minutes` | `integer` | no |  |  |
| `manual_confirmation` | `boolean` | no | `false` |  |
| `max_reschedules` | `integer` | no | `1` |  |
| `default_closure_status` | `varchar(20)` | no | `'COMPLETED'` |  |
| `auto_close_delay_hours` | `integer` | no | `24` |  |
| `effective_from` | `timestamptz` | no | `now()` |  |
| `replaced_at` | `timestamptz` | sí |  |  |

- EXCLUDE `ex_organization_policies_solape`: `EXCLUDE USING gist (organization_id WITH =, tstzrange(effective_from, replaced_at) WITH &&)`
- UNIQUE `uk_organization_policies_version`: `UNIQUE (organization_id, version)`
- CHECK `ck_organization_policies_auto_close_hours`: `CHECK ((auto_close_delay_hours > 0))`
- CHECK `ck_organization_policies_cancel`: `CHECK ((free_cancellation_window_minutes >= 0))`
- CHECK `ck_organization_policies_closure_status`: `CHECK ((default_closure_status IN ('COMPLETED', 'NO_SHOW')))`
- CHECK `ck_organization_policies_notice`: `CHECK (((booking_notice_minutes_min >= 0) AND (booking_notice_minutes_min <= booking_notice_minutes_max)))`
- CHECK `ck_organization_policies_reschedules`: `CHECK ((max_reschedules >= 0))`
- CHECK `ck_organization_policies_version`: `CHECK ((version > 0))`
- CHECK `ck_organization_policies_vigencia`: `CHECK (((replaced_at IS NULL) OR (replaced_at > effective_from)))`
- UNIQUE (índice) `ux_organization_policies_vigente`: `USING btree (organization_id) WHERE (replaced_at IS NULL)`
- Índice `ex_organization_policies_solape`: `USING gist (organization_id, tstzrange(effective_from, replaced_at))`


#### `locations`

Sedes de un proveedor.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `organization_id` | `uuid` | no |  | FK → `organizations` (restrict) |
| `name` | `varchar(120)` | no |  |  |
| `address` | `varchar(200)` | no |  |  |
| `city_id` | `uuid` | no |  | FK → `cities` (restrict) |
| `timezone` | `varchar(60)` | sí |  |  |
| `status` | `varchar(20)` | no | `'ACTIVE'` |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- UNIQUE `uk_locations_org_name`: `UNIQUE (organization_id, name)`
- CHECK `ck_locations_address`: `CHECK ((length(btrim(address)) > 0))`
- CHECK `ck_locations_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_locations_status`: `CHECK ((status IN ('ACTIVE', 'INACTIVE')))`
- Índice `ix_locations_city`: `USING btree (city_id)`
- Trigger `tg_locations_proveedor_inmutable`: El proveedor de una sede, un servicio o un tipo de recurso no cambia


#### `organization_status_changes`

Historia de estados de un proveedor, con motivo obligatorio (HU-003).

*Sprint 2: normalizada: sale de `account_status_changes`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `organization_id` | `uuid` | no |  | FK → `organizations` (restrict) |
| `from_status` | `varchar(30)` | sí |  |  |
| `to_status` | `varchar(30)` | no |  |  |
| `reason` | `varchar(500)` | no |  |  |
| `affected_bookings` | `integer` | no | `0` |  |
| `changed_by` | `uuid` | sí |  |  |
| `changed_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_organization_status_changes_count`: `CHECK ((affected_bookings >= 0))`
- CHECK `ck_organization_status_changes_from`: `CHECK (((from_status IS NULL) OR (from_status IN ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED'))))`
- CHECK `ck_organization_status_changes_reason`: `CHECK ((length(btrim(reason)) > 0))`
- CHECK `ck_organization_status_changes_to`: `CHECK ((to_status IN ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')))`
- Índice `ix_organization_status_changes_org`: `USING btree (organization_id, changed_at DESC)`

</details>

<details>
<summary><b>Servicios y recursos</b> · services, service_locations, resource_types, service_resource_requirements, resources, resource_maintenances</summary>


#### `services`

Servicios ofertados (HU-004). customer_capacity 1 = individual, > 1 = grupal.

*Sprint 2: V3 del equipo: nace `INACTIVE`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `organization_id` | `uuid` | no |  | FK → `organizations` (restrict) |
| `name` | `varchar(120)` | no |  |  |
| `description` | `varchar(500)` | sí |  |  |
| `duration_minutes` | `integer` | no |  |  |
| `preparation_minutes` | `integer` | no | `0` |  |
| `cleanup_minutes` | `integer` | no | `0` |  |
| `price` | `numeric(12,2)` | no |  |  |
| `currency_id` | `uuid` | no |  | FK → `currencies` (restrict) |
| `customer_capacity` | `integer` | no | `1` |  |
| `status` | `varchar(20)` | no | `'INACTIVE'` |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- UNIQUE `uk_services_org_name`: `UNIQUE (organization_id, name)`
- CHECK `ck_services_capacity`: `CHECK ((customer_capacity >= 1))`
- CHECK `ck_services_duration`: `CHECK ((duration_minutes > 0))`
- CHECK `ck_services_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_services_prep`: `CHECK (((preparation_minutes >= 0) AND (cleanup_minutes >= 0)))`
- CHECK `ck_services_price`: `CHECK ((price >= (0)))`
- CHECK `ck_services_status`: `CHECK ((status IN ('ACTIVE', 'INACTIVE')))`
- Índice `ix_services_currency`: `USING btree (currency_id)`
- Trigger `tg_services_proveedor_inmutable`: El proveedor de una sede, un servicio o un tipo de recurso no cambia


#### `service_locations`

En qué sedes se presta cada servicio (HU-004).

*Sprint 2: normalizada: sin `organization_id`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `service_id` | `uuid` | no |  | PK, FK → `services` (cascade) |
| `location_id` | `uuid` | no |  | PK, FK → `locations` (cascade) |

- PK `pk_service_locations`: `PRIMARY KEY (service_id, location_id)`
- Índice `ix_service_locations_location`: `USING btree (location_id)`
- Trigger `tg_service_locations_mismo_proveedor`: El servicio y la sede son del mismo proveedor
- Trigger `tg_service_locations_quita_de_agendas`: Si un servicio deja de prestarse en una sede, por borrado o edición, sale de las agendas de esa sede


#### `resource_types`

Tipos de recurso no consumible: sala, silla, especialista.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `organization_id` | `uuid` | no |  | FK → `organizations` (restrict) |
| `name` | `varchar(80)` | no |  |  |
| `description` | `varchar(300)` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- UNIQUE `uk_resource_types_org_name`: `UNIQUE (organization_id, name)`
- CHECK `ck_resource_types_name`: `CHECK ((length(btrim(name)) > 0))`
- Trigger `tg_resource_types_proveedor_inmutable`: El proveedor de una sede, un servicio o un tipo de recurso no cambia


#### `service_resource_requirements`

Cuántos recursos de cada tipo exige un servicio.

*Sprint 2: normalizada: sin `id` ni `organization_id`, PK natural.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `service_id` | `uuid` | no |  | PK, FK → `services` (cascade) |
| `resource_type_id` | `uuid` | no |  | PK, FK → `resource_types` (restrict) |
| `quantity_required` | `integer` | no | `1` |  |

- PK `pk_service_resource_requirements`: `PRIMARY KEY (service_id, resource_type_id)`
- CHECK `ck_service_resource_requirements_qty`: `CHECK ((quantity_required > 0))`
- Índice `ix_service_resource_requirements_type`: `USING btree (resource_type_id)`
- Trigger `tg_service_resource_requirements_mismo_proveedor`: El servicio y el tipo de recurso son del mismo proveedor


#### `resources`

Recurso concreto en una sede, con capacidad y estado (HU-009).

*Sprint 2: V7 del equipo: capacidad y estado; normalizada: sin `organization_id`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `resource_type_id` | `uuid` | no |  | FK → `resource_types` (restrict) |
| `location_id` | `uuid` | no |  | FK → `locations` (restrict) |
| `name` | `varchar(120)` | no |  |  |
| `capacity` | `integer` | no | `1` |  |
| `status` | `varchar(20)` | no | `'ACTIVE'` |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- UNIQUE `uk_resources_location_name`: `UNIQUE (location_id, name)`
- CHECK `ck_resources_capacity`: `CHECK ((capacity >= 1))`
- CHECK `ck_resources_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_resources_status`: `CHECK ((status IN ('ACTIVE', 'RETIRED')))`
- Índice `ix_resources_type`: `USING btree (resource_type_id)`
- Trigger `tg_resources_coherencia`: Tipo y sede del mismo proveedor; un recurso con sesiones o agenda no cambia de sede


#### `resource_maintenances`

Periodos de mantenimiento: el recurso no genera disponibilidad (HU-009).

*Sprint 2: V7 del equipo.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `resource_id` | `uuid` | no |  | FK → `resources` (cascade) |
| `starts_at` | `timestamptz` | no |  |  |
| `ends_at` | `timestamptz` | no |  |  |
| `reason` | `varchar(300)` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- EXCLUDE `ex_resource_maintenances_solape`: `EXCLUDE USING gist (resource_id WITH =, tstzrange(starts_at, ends_at) WITH &&)`
- CHECK `ck_resource_maintenances_rango`: `CHECK ((ends_at > starts_at))`
- Índice `ex_resource_maintenances_solape`: `USING gist (resource_id, tstzrange(starts_at, ends_at))`

</details>

<details>
<summary><b>Agendas</b> · agendas, agenda_services, schedules, agenda_exceptions</summary>


#### `agendas`

Agenda de una sede o de un recurso, nunca de los dos: granularidad, vigencia y servicios (HU-006).

*Sprint 2: V8 del equipo; normalizada: sin `organization_id`, y es de una sede o de un recurso, no de los dos.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `location_id` | `uuid` | sí |  | FK → `locations` (restrict) |
| `resource_id` | `uuid` | sí |  | FK → `resources` (restrict) |
| `name` | `varchar(120)` | no |  |  |
| `slot_minutes` | `smallint` | no |  |  |
| `valid_from` | `date` | no |  |  |
| `valid_until` | `date` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- EXCLUDE `ex_agendas_recurso_solape`: `EXCLUDE USING gist (resource_id WITH =, daterange(valid_from, valid_until, '[]') WITH &&) WHERE ((resource_id IS NOT NULL))`
- EXCLUDE `ex_agendas_sede_solape`: `EXCLUDE USING gist (location_id WITH =, daterange(valid_from, valid_until, '[]') WITH &&) WHERE ((location_id IS NOT NULL))`
- UNIQUE `uk_agendas_location_name`: `UNIQUE (location_id, name)`
- UNIQUE `uk_agendas_resource_name`: `UNIQUE (resource_id, name)`
- CHECK `ck_agendas_duenio`: `CHECK (((location_id IS NULL) <> (resource_id IS NULL)))`
- CHECK `ck_agendas_name`: `CHECK ((length(btrim(name)) > 0))`
- CHECK `ck_agendas_slot`: `CHECK ((slot_minutes IN (15, 30, 60)))`
- CHECK `ck_agendas_vigencia`: `CHECK (((valid_until IS NULL) OR (valid_until >= valid_from)))`
- Índice `ex_agendas_recurso_solape`: `USING gist (resource_id, daterange(valid_from, valid_until, '[]')) WHERE (resource_id IS NOT NULL)`
- Índice `ex_agendas_sede_solape`: `USING gist (location_id, daterange(valid_from, valid_until, '[]')) WHERE (location_id IS NOT NULL)`
- Trigger `tg_agendas_servicios_en_sede`: Si la agenda cambia de sede o de recurso, sus servicios se prestan en la sede nueva


#### `agenda_services`

Servicios reservables en una agenda (HU-006).

*Sprint 2: V8 del equipo; normalizada: sin `location_id`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `agenda_id` | `uuid` | no |  | PK, FK → `agendas` (cascade) |
| `service_id` | `uuid` | no |  | PK, FK → `services` (cascade) |

- PK `pk_agenda_services`: `PRIMARY KEY (agenda_id, service_id)`
- Índice `ix_agenda_services_service`: `USING btree (service_id)`
- Trigger `tg_agenda_services_en_sede`: El servicio se presta en la sede de la agenda (HU-006)


#### `schedules`

Bloques horarios semanales de una agenda (HU-006).

*Sprint 2: V8 del equipo: bloques de una agenda.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `agenda_id` | `uuid` | no |  | FK → `agendas` (cascade) |
| `day_of_week` | `smallint` | no |  |  |
| `start_time` | `time` | no |  |  |
| `end_time` | `time` | no |  |  |
| `active` | `boolean` | no | `true` |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- EXCLUDE `ex_schedules_solape`: `EXCLUDE USING gist (agenda_id WITH =, day_of_week WITH =, timerange(start_time, end_time) WITH &&) WHERE (active)`
- CHECK `ck_schedules_dow`: `CHECK (((day_of_week >= 1) AND (day_of_week <= 7)))`
- CHECK `ck_schedules_rango`: `CHECK ((end_time > start_time))`
- Índice `ex_schedules_solape`: `USING gist (agenda_id, day_of_week, timerange(start_time, end_time)) WHERE active`
- Índice `ix_schedules_agenda`: `USING btree (agenda_id)`


#### `agenda_exceptions` · **[S2 nueva]**

Festivos, cierres y jornadas recortadas de una agenda.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `agenda_id` | `uuid` | no |  | FK → `agendas` (cascade) |
| `exception_date` | `date` | no |  |  |
| `start_time` | `time` | sí |  |  |
| `end_time` | `time` | sí |  |  |
| `reason` | `varchar(300)` | no |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- EXCLUDE `ex_agenda_exceptions_solape`: `EXCLUDE USING gist (agenda_id WITH =, exception_date WITH =, timerange(COALESCE(start_time, '00:00:00'), COALESCE(end_time, '24:00:00')) WITH &&)`
- CHECK `ck_agenda_exceptions_franja`: `CHECK ((((start_time IS NULL) AND (end_time IS NULL)) OR ((start_time IS NOT NULL) AND (end_time IS NOT NULL) AND (end_time > start_time))))`
- CHECK `ck_agenda_exceptions_reason`: `CHECK ((length(btrim(reason)) > 0))`
- Índice `ex_agenda_exceptions_solape`: `USING gist (agenda_id, exception_date, timerange(COALESCE(start_time, '00:00:00'), COALESCE(end_time, '24:00:00')))`

</details>

<details>
<summary><b>Reservas y pagos</b> · sessions, bookings, session_resources, booking_status_changes, booking_reschedules, booking_reviews, waitlist_entries, payments</summary>


#### `sessions` · **[S2 nueva]**

Un servicio en una sede y a una hora. Individual: una reserva; grupal: varias, hasta el cupo.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `service_id` | `uuid` | no |  | FK compuesta → `service_locations` |
| `location_id` | `uuid` | no |  | FK compuesta → `service_locations` |
| `starts_at` | `timestamptz` | no |  |  |
| `ends_at` | `timestamptz` | no |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- FK `fk_sessions_service_location`: `FOREIGN KEY (service_id, location_id) REFERENCES service_locations(service_id, location_id) ON DELETE RESTRICT`
- CHECK `ck_sessions_rango`: `CHECK ((ends_at > starts_at))`
- Índice `ix_sessions_location_starts`: `USING btree (location_id, starts_at)`
- Índice `ix_sessions_service_starts`: `USING btree (service_id, starts_at)`
- Trigger `tg_sessions_coherencia`: La sesión no cambia de servicio; si se mueve, sus recursos siguen en la sede y libres


#### `bookings`

Reserva de un cliente en una sesión. policy_id y currency_id congelan las condiciones y la moneda al crearla.

*Sprint 3: `code`, otra clave candidata, para buscar la reserva y para el comprobante (HU-018, V11 del equipo).*

*Sprint 2: normalizada: el servicio, la sede y el horario pasan a `sessions`; sin `organization_id`; con `currency_id`.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `code` | `varchar(64)` | no | `f_codigo_reserva()` | UNIQUE |
| `client_id` | `uuid` | no |  | FK → `clients` (restrict) |
| `session_id` | `uuid` | no |  | FK → `sessions` (restrict) |
| `policy_id` | `uuid` | no |  | FK → `organization_policies` (restrict) |
| `attendees` | `integer` | no | `1` |  |
| `total_price` | `numeric(12,2)` | no |  |  |
| `currency_id` | `uuid` | no |  | FK → `currencies` (restrict) |
| `status` | `varchar(20)` | no | `'RESERVED'` |  |
| `cancelled_at` | `timestamptz` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_bookings_attendees`: `CHECK ((attendees > 0))`
- CHECK `ck_bookings_cancel`: `CHECK (((status = 'CANCELLED') = (cancelled_at IS NOT NULL)))`
- CHECK `ck_bookings_code`: `CHECK ((code ~ '^RSV-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$'))`
- CHECK `ck_bookings_price`: `CHECK ((total_price >= (0)))`
- CHECK `ck_bookings_status`: `CHECK ((status IN ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')))`
- Índice `ix_bookings_client`: `USING btree (client_id)`
- Índice `ix_bookings_policy`: `USING btree (policy_id)`
- Índice `ix_bookings_session`: `USING btree (session_id)`
- Índice `ix_bookings_vivas`: `USING btree (session_id) WHERE (status IN ('RESERVED', 'CONFIRMED'))`
- Trigger `tg_bookings_anticipacion`: **[S3]** HU-012 y HU-014: la cita cae dentro de la ventana de anticipación de la política
- Trigger `tg_bookings_avisos`: **[S3]** HU-015: encola avisos y programa los recordatorios del proveedor
- Trigger `tg_bookings_coherencia`: Política del proveedor y vigente al reservar, que ya no cambia; precio en la moneda del servicio; otra sesión sólo del mismo servicio
- Trigger `tg_bookings_cruce_cliente`: **[S3]** HU-012: un cliente no tiene dos reservas vivas que se crucen
- Trigger `tg_bookings_exige_historial`: **[S3]** HU-013 y HU-016: un cambio de estado exige su fila en booking_status_changes
- Trigger `tg_bookings_exige_reprogramacion`: **[S3]** HU-014: cambiar de sesión exige su fila en booking_reschedules
- Trigger `tg_bookings_momento_del_estado`: **[S3]** HU-013 y HU-016: no se cancela una cita que empezó ni se registra asistencia antes de que empiece
- Trigger `tg_bookings_reglas`: HU-001 a 004: estados válidos, proveedor, servicio y sede activos, cliente no suspendido, verificado para confirmar, y cupo de la sesión
- Trigger `tg_sessions_libera_recursos`: Una sesión sin reservas vivas suelta sus recursos


#### `session_resources` · **[S2 nueva]**

Recursos que ocupa una sesión; un trigger impide que un recurso quede en dos sesiones a la vez.

*Sprint 2: reemplaza a `booking_resources`: el recurso es de la sesión, sin copias del horario.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `session_id` | `uuid` | no |  | PK, FK → `sessions` (cascade) |
| `resource_id` | `uuid` | no |  | PK, FK → `resources` (restrict) |

- PK `pk_session_resources`: `PRIMARY KEY (session_id, resource_id)`
- Índice `ix_session_resources_resource`: `USING btree (resource_id)`
- Trigger `tg_session_resources_reglas`: El recurso está activo, en la sede de la sesión y no está ocupado por otra sesión que se cruce


#### `booking_status_changes`

Historia de estados de una reserva.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `booking_id` | `uuid` | no |  | FK → `bookings` (restrict) |
| `from_status` | `varchar(20)` | sí |  |  |
| `to_status` | `varchar(20)` | no |  |  |
| `reason` | `varchar(300)` | sí |  |  |
| `changed_by` | `uuid` | sí |  |  |
| `changed_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_booking_status_changes_cambio`: `CHECK ((from_status IS DISTINCT FROM (to_status)))`
- CHECK `ck_booking_status_changes_from`: `CHECK (((from_status IS NULL) OR (from_status IN ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW'))))`
- CHECK `ck_booking_status_changes_reason`: `CHECK (((to_status <> 'CANCELLED') OR (length(btrim((COALESCE(reason, '')))) > 0)))`
- CHECK `ck_booking_status_changes_to`: `CHECK ((to_status IN ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')))`
- Índice `ix_booking_status_changes_booking`: `USING btree (booking_id)`


#### `booking_reschedules` · **[S3 nueva]**

Reprogramaciones de una reserva: de qué sesión a cuál, quién y por qué (HU-014).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `booking_id` | `uuid` | no |  | FK → `bookings` (restrict) |
| `from_session_id` | `uuid` | no |  | FK → `sessions` (restrict) |
| `to_session_id` | `uuid` | no |  | FK → `sessions` (restrict) |
| `reason` | `varchar(300)` | sí |  |  |
| `rescheduled_by` | `uuid` | sí |  |  |
| `rescheduled_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_booking_reschedules_cambio`: `CHECK ((from_session_id <> to_session_id))`
- CHECK `ck_booking_reschedules_reason`: `CHECK (((reason IS NULL) OR (length(btrim(reason)) > 0)))`
- Índice `ix_booking_reschedules_booking`: `USING btree (booking_id, rescheduled_at)`
- Índice `ix_booking_reschedules_from`: `USING btree (from_session_id)`
- Índice `ix_booking_reschedules_to`: `USING btree (to_session_id)`
- Trigger `tg_booking_reschedules_reglas`: **[S3]** HU-014: reprogramar una reserva vigente, desde su sesión, al mismo servicio y sede, sin pasar el tope


#### `booking_reviews` · **[S2 nueva]**

Calificación de 1 a 5 de una reserva completada.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `booking_id` | `uuid` | no |  | FK → `bookings` (restrict), UNIQUE |
| `rating` | `smallint` | no |  |  |
| `comment` | `varchar(1000)` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_booking_reviews_comment`: `CHECK (((comment IS NULL) OR (length(btrim(comment)) > 0)))`
- CHECK `ck_booking_reviews_rating`: `CHECK (((rating >= 1) AND (rating <= 5)))`
- Trigger `tg_booking_reviews_completada`: Sólo se califica una reserva completada


#### `waitlist_entries` · **[S2 nueva]**

Lista de espera por servicio, sede y día.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `client_id` | `uuid` | no |  | FK → `clients` (cascade) |
| `service_id` | `uuid` | no |  | FK compuesta → `service_locations` |
| `location_id` | `uuid` | no |  | FK compuesta → `service_locations` |
| `desired_date` | `date` | no |  |  |
| `attendees` | `integer` | no | `1` |  |
| `status` | `varchar(20)` | no | `'WAITING'` |  |
| `booking_id` | `uuid` | sí |  | FK → `bookings` (restrict), UNIQUE |
| `notified_at` | `timestamptz` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- FK `fk_waitlist_entries_service_location`: `FOREIGN KEY (service_id, location_id) REFERENCES service_locations(service_id, location_id) ON DELETE CASCADE`
- CHECK `ck_waitlist_entries_attendees`: `CHECK ((attendees > 0))`
- CHECK `ck_waitlist_entries_booked`: `CHECK (((status = 'BOOKED') = (booking_id IS NOT NULL)))`
- CHECK `ck_waitlist_entries_notified`: `CHECK ((((status) NOT IN ('NOTIFIED', 'BOOKED', 'EXPIRED')) OR (notified_at IS NOT NULL)))`
- CHECK `ck_waitlist_entries_status`: `CHECK ((status IN ('WAITING', 'NOTIFIED', 'BOOKED', 'EXPIRED', 'CANCELLED')))`
- UNIQUE (índice) `ux_waitlist_entries_activa`: `USING btree (client_id, service_id, location_id, desired_date) WHERE (status IN ('WAITING', 'NOTIFIED'))`
- Índice `ix_waitlist_entries_client`: `USING btree (client_id)`
- Índice `ix_waitlist_entries_service_location`: `USING btree (service_id, location_id, desired_date)`
- Trigger `tg_waitlist_entries_reserva`: La reserva en que terminó la espera es del mismo cliente, servicio y sede


#### `payments` · **[S2 nueva]**

Pagos y reembolsos de una reserva.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `booking_id` | `uuid` | no |  | FK → `bookings` (restrict) |
| `amount` | `numeric(12,2)` | no |  |  |
| `currency_id` | `uuid` | no |  | FK → `currencies` (restrict) |
| `method` | `varchar(20)` | no |  |  |
| `status` | `varchar(20)` | no | `'PENDING'` |  |
| `external_reference` | `varchar(100)` | sí |  | UNIQUE |
| `paid_at` | `timestamptz` | sí |  |  |
| `refunded_at` | `timestamptz` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_payments_amount`: `CHECK ((amount > (0)))`
- CHECK `ck_payments_external_reference`: `CHECK (((external_reference IS NULL) OR (length(btrim(external_reference)) > 0)))`
- CHECK `ck_payments_fechas`: `CHECK ((((status IN ('PENDING', 'FAILED')) AND (paid_at IS NULL) AND (refunded_at IS NULL)) OR ((status = 'PAID') AND (paid_at IS NOT NULL) AND (refunded_at IS NULL)) OR ((status = 'REFUNDED') AND (paid_at IS NOT NULL) AND (refunded_at IS NOT NULL) AND (refunded_at >= paid_at))))`
- CHECK `ck_payments_method`: `CHECK ((method IN ('CARD', 'BANK_TRANSFER', 'CASH')))`
- CHECK `ck_payments_status`: `CHECK ((status IN ('PENDING', 'PAID', 'FAILED', 'REFUNDED')))`
- UNIQUE (índice) `ux_payments_vigente`: `USING btree (booking_id) WHERE (status IN ('PENDING', 'PAID'))`
- Índice `ix_payments_booking`: `USING btree (booking_id)`

</details>

<details>
<summary><b>Notificaciones, reportes y auditoría</b> · sent_emails, organization_booking_reminders, booking_notices, resource_occupancy_daily, audit_log, audit_log_changes</summary>


#### `sent_emails`

Correos guardados en vez de enviados por SMTP (ADR-0007).

*Sprint 2: V6 del equipo.*

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `recipient` | `varchar(160)` | no |  |  |
| `subject` | `varchar(200)` | no |  |  |
| `body` | `text` | no |  |  |
| `sent_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_sent_emails_recipient`: `CHECK ((recipient ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'))`
- CHECK `ck_sent_emails_subject`: `CHECK ((length(btrim(subject)) > 0))`
- Índice `ix_sent_emails_recipient`: `USING btree (lower(recipient), sent_at DESC)`


#### `organization_booking_reminders` · **[S3 nueva]**

Cuántos minutos antes de la cita recuerda cada proveedor (HU-015).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `organization_id` | `uuid` | no |  | PK, FK → `organizations` (cascade) |
| `minutes_before` | `integer` | no |  | PK |
| `created_at` | `timestamptz` | no | `now()` |  |

- PK `pk_organization_booking_reminders`: `PRIMARY KEY (organization_id, minutes_before)`
- CHECK `ck_organization_booking_reminders_minutes`: `CHECK (((minutes_before >= 15) AND (minutes_before <= 10080)))`


#### `booking_notices` · **[S3 nueva]**

Cola de avisos y recordatorios de una reserva, llenada por tg_bookings_avisos (HU-015).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | PK |
| `booking_id` | `uuid` | no |  | FK → `bookings` (restrict) |
| `kind` | `varchar(20)` | no |  |  |
| `due_at` | `timestamptz` | no |  |  |
| `processed_at` | `timestamptz` | sí |  |  |
| `created_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_booking_notices_kind`: `CHECK ((kind IN ('CREATED', 'CONFIRMED', 'CANCELLED', 'RESCHEDULED', 'REMINDER')))`
- CHECK `ck_booking_notices_proceso`: `CHECK (((processed_at IS NULL) OR (processed_at >= created_at)))`
- UNIQUE (índice) `ux_booking_notices_recordatorio`: `USING btree (booking_id, due_at) WHERE (kind = 'REMINDER')`
- Índice `ix_booking_notices_booking`: `USING btree (booking_id)`
- Índice `ix_booking_notices_pendientes`: `USING btree (due_at) WHERE (processed_at IS NULL)`


#### `resource_occupancy_daily` · **[S2 nueva]**

Ocupación diaria por recurso, calculada por fn_calcular_ocupacion.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `resource_id` | `uuid` | no |  | PK, FK → `resources` (cascade) |
| `occupancy_date` | `date` | no |  | PK |
| `available_minutes` | `integer` | no |  |  |
| `booked_minutes` | `integer` | no |  |  |
| `sessions_count` | `integer` | no |  |  |
| `calculated_at` | `timestamptz` | no | `now()` |  |

- PK `pk_resource_occupancy_daily`: `PRIMARY KEY (resource_id, occupancy_date)`
- CHECK `ck_resource_occupancy_daily_minutos`: `CHECK (((available_minutes >= 0) AND (booked_minutes >= 0) AND (sessions_count >= 0)))`
- Índice `ix_resource_occupancy_daily_date`: `USING btree (occupancy_date)`


#### `audit_log` · **[S2 nueva]**

Auditoría de cambios en tablas sensibles, escrita por trigger: quién, cuándo y sobre qué fila.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `id` | `bigint` | no | `generated always as identity` | PK |
| `table_name` | `varchar(63)` | no |  |  |
| `operation` | `varchar(6)` | no |  |  |
| `record_id` | `text` | no |  |  |
| `db_user` | `varchar(63)` | no | `SESSION_USER` |  |
| `app_user_id` | `uuid` | sí |  |  |
| `changed_at` | `timestamptz` | no | `now()` |  |

- CHECK `ck_audit_log_operation`: `CHECK ((operation IN ('INSERT', 'UPDATE', 'DELETE')))`
- CHECK `ck_audit_log_table`: `CHECK ((length(btrim(table_name)) > 0))`
- Índice `ix_audit_log_registro`: `USING btree (table_name, record_id, changed_at DESC)`


#### `audit_log_changes` · **[S2 nueva]**

Columnas que cambió cada evento de audit_log, con el valor de antes y el de después.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| `audit_log_id` | `bigint` | no |  | PK, FK → `audit_log` (cascade) |
| `column_name` | `varchar(63)` | no |  | PK |
| `old_value` | `text` | sí |  |  |
| `new_value` | `text` | sí |  |  |

- PK `pk_audit_log_changes`: `PRIMARY KEY (audit_log_id, column_name)`
- CHECK `ck_audit_log_changes_cambio`: `CHECK ((old_value IS DISTINCT FROM new_value))`

</details>

### Normalización

**Las 35 tablas están en BCNF.** Lo reviso con la regla del curso (Pres09): una tabla con una sola
clave candidata se puede revisar con 2FN y 3FN, pero una con más de una se lleva directamente a
BCNF, que exige que todo determinante sea clave candidata. Varias tablas de este modelo tienen dos
claves, por ejemplo `id` y `(location_id, name)`, así que la vara para todas es BCNF.

**Las cuatro que no llegaban.** Tres tablas que venían del equipo y el primer diseño de la auditoría
no estaban en BCNF. Así quedaron:

| Tabla | Qué rompía la forma normal | Cómo quedó |
|---|---|---|
| `bookings` | `session_id → service_id, location_id, starts_at, ends_at`. En un servicio grupal varias reservas comparten sesión, y cada una repetía el servicio, la sede y el horario. `session_id` no es clave de la reserva, así que la dependencia era transitiva: `id → session_id → starts_at` | Nueva tabla **`sessions`** con esos cuatro datos. La reserva sólo guarda `session_id`. Que las reservas de un taller tengan la misma hora ya no lo revisa un trigger: es imposible que no la tengan, porque la hora está una sola vez |
| `booking_resources` | `booking_id → session_id, starts_at, ends_at, status`, una dependencia parcial respecto a la clave `(booking_id, resource_id)`. Copiaba el horario de la reserva porque el `EXCLUDE` contra la sobreocupación necesita el rango en la misma fila | **`session_resources (session_id, resource_id)`**, sin copias. El recurso se asigna a la sesión, que es lo que de verdad lo ocupa: el salón de un taller se ocupa una vez, no una por reserva. La sobreocupación la impide `tg_session_resources_reglas` |
| `agendas` | `resource_id → location_id`. Una agenda de recurso guardaba también la sede, que ya sale del recurso, y `resource_id` no es clave | Una agenda es **de una sede o de un recurso, nunca de los dos**: `ck_agendas_duenio` exige que sólo una de las dos columnas tenga valor. La sede de una agenda de recurso sale del recurso |
| `audit_log` | `old_data` y `new_data` eran `jsonb` con la fila completa: un valor compuesto, no atómico. Ni 1FN | **`audit_log`** guarda quién cambió qué fila y cuándo, y **`audit_log_changes`** una fila por columna que cambió, con el valor de antes y el de después |

El cambio de `booking_resources` tiene un costo, y lo dejo dicho. Un `EXCLUDE` es declarativo: no
hay forma de saltárselo. El trigger que lo reemplaza es código, y además dos asignaciones
simultáneas del mismo recurso podrían verse mutuamente como libres. Por eso el trigger toma un
candado por recurso (`pg_advisory_xact_lock`) antes de revisar. Lo probé con dos transacciones al
mismo tiempo sobre la misma silla y la misma hora: sin el candado entraron las dos, y con él la
segunda esperó a la primera y fue rechazada. Mover una sesión toma los mismos candados, en orden,
para que dos movimientos simultáneos no se bloqueen entre sí. Y quien asigna un recurso lee la sesión
con `for share`: si otra transacción la está moviendo, espera y revisa contra el horario nuevo.
También lo probé con dos transacciones a la vez.

**Lo que quité de las tablas del equipo y cómo se garantiza ahora.** Había otras siete redundancias:
cuatro del Sprint 1 y tres que llegaron con V7 y V8. Todas existían para lo mismo, impedir que se
mezclaran datos de dos proveedores o de dos sedes con una FK compuesta:

| Tabla | Dependencia que rompía la forma normal | La regla ahora la cumple |
|---|---|---|
| `service_locations` | `service_id → organization_id`: parcial, 2FN | `tg_service_locations_mismo_proveedor` |
| `service_resource_requirements` | `service_id → organization_id`: parcial, 2FN | `tg_service_resource_requirements_mismo_proveedor` |
| `agenda_services` | `agenda_id → location_id`: parcial, 2FN | `tg_agenda_services_en_sede` y `tg_agendas_servicios_en_sede` |
| `resources` | `location_id → organization_id`: transitiva, 3FN | `tg_resources_coherencia` |
| `agendas` | `location_id → organization_id`: transitiva, 3FN | sale de la sede; no hace falta regla |
| `bookings` | `service_id → organization_id`: transitiva, 3FN | `tg_bookings_coherencia` (la política es del proveedor del servicio) |
| `booking_resources` | `resource_id → location_id`: parcial, 2FN | `tg_session_resources_reglas` y `tg_sessions_coherencia` |

Es el mismo intercambio de arriba: una FK compuesta no se puede saltar, y un trigger es código. A
cambio, cada dato vive en un solo lugar y cada trigger es una sola consulta. Para que las reglas
tampoco se rompan desde la tabla padre, el proveedor de una sede, un servicio o un tipo de recurso
no cambia (`fn_proveedor_inmutable`), una sesión no cambia de servicio, un recurso con sesiones o con
agenda no cambia de sede, una sesión no se mueve a una sede donde no están sus recursos, y si se
edita una fila de `service_locations` el servicio sale de las agendas de la sede vieja. Las pruebas
20 a 43 de [`pruebas-integridad.sql`](pruebas-integridad.sql) intentan romper cada regla, de frente y
desde la tabla padre, y la base las rechaza todas.

**Las tablas nuevas:**

| Tabla | Dependencias funcionales | Forma | Por qué |
|---|---|---|---|
| `sessions` | `id → service_id, location_id, starts_at, ends_at` | BCNF | El único determinante es la clave. `ends_at` no depende de `(service_id, starts_at)`: congela la duración que tenía el servicio al reservar, y esa duración puede cambiar después |
| `session_resources` | ninguna fuera de la clave `(session_id, resource_id)` | BCNF | Sólo tiene la clave |
| `agenda_exceptions` | `id → agenda_id, exception_date, start_time, end_time, reason` | BCNF | El único determinante es la clave |
| `booking_reviews` | `id → todo`; `booking_id → todo` | BCNF | Las dos son claves candidatas. No guarda cliente ni servicio: ya se llega a ellos por `booking_id`, y guardarlos sería repetir entre tablas un dato que puede quedar distinto |
| `waitlist_entries` | `id → todo`; `booking_id → todo`, cuando no es nulo | BCNF | `booking_id` es `UNIQUE`: una reserva sale de a lo sumo una espera. Aquí cliente, servicio y sede sí se guardan, porque la espera existe antes que la reserva. Cuando termina en una, esos datos se repiten con los de la reserva: no rompe BCNF, pero es redundancia entre tablas, y la vigilan `tg_waitlist_entries_reserva` y `tg_bookings_coherencia`, que no deja llevar esa reserva a otra sede |
| `payments` | `id → todo`; `external_reference → todo` | BCNF | `amount` y `currency_id` no se derivan de la reserva: son lo que cobró la pasarela, y una tarjeta internacional se cobra en otra moneda |
| `resource_occupancy_daily` | `(resource_id, occupancy_date) → minutos, sesiones` | BCNF | Todo depende de la clave completa |
| `audit_log` | `id → table_name, operation, record_id, db_user, app_user_id, changed_at` | BCNF | El único determinante es la clave. Sobre `record_id`, ver abajo |
| `audit_log_changes` | `(audit_log_id, column_name) → old_value, new_value` | BCNF | Todo depende de la clave completa |

**`audit_log.record_id`.** Es la clave de la fila auditada, escrita como texto. En seis de las siete
tablas auditadas es un `uuid`, un valor atómico. La excepción es `organization_members`, cuya clave es
`(organization_id, user_id)`: ahí `record_id` guarda los dos valores separados por `/`. Lo dejo así a
conciencia. Es un identificador que sólo se compara entero contra otro, nunca se consulta por partes,
y la alternativa, una columna por cada parte posible de clave de cada tabla auditada, ataría la
auditoría al diseño de todas las demás. Es distinto del `jsonb` que quité: ese guardaba la fila entera
y la consulta de auditoría sí lo abría columna por columna.

`resource_occupancy_daily` además es un dato derivado: se podría calcular desde las sesiones y las
agendas. La guardo igual, como en un data mart, porque el reporte de un mes por recurso pasa de
recorrer todas las sesiones a leer 30 filas. La llena `fn_calcular_ocupacion`, que reescribe el día
completo, y rol_app sólo tiene permiso de leerla.

**Lo del Sprint 3:**

| Tabla | Dependencias funcionales | Forma | Por qué |
|---|---|---|---|
| `bookings` | `id → todo`; `code → todo` | BCNF | `code` es una segunda clave candidata. Los dos determinantes son claves, así que agregar la columna no saca a la tabla de BCNF |
| `organization_policies` | `id → todo`; `(organization_id, version) → todo` | BCNF | Las cuatro reglas nuevas dependen de la versión de la política, no del proveedor: si el proveedor cambia una regla, nace otra versión |
| `booking_reschedules` | `id → booking_id, from_session_id, to_session_id, reason, rescheduled_by, rescheduled_at` | BCNF | El único determinante es la clave. No guarda el servicio ni la hora de las sesiones: salen de las FK |
| `organization_booking_reminders` | `(organization_id, minutes_before) → created_at` | BCNF | Todo depende de la clave completa. Un recordatorio por fila, y no una lista en una columna, para que cada valor sea atómico (1FN) |
| `booking_notices` | `id → booking_id, kind, due_at, processed_at, created_at` | BCNF | El único determinante es la clave. `due_at` se guarda aunque un recordatorio se pueda calcular con la sesión y los minutos del proveedor: es la hora con que se programó el aviso, y el proceso que envía la busca por índice. Si la reserva se mueve, `tg_bookings_avisos` borra los pendientes y los vuelve a programar |

Lo que **no** guardé es la parte de normalización de este sprint. El equipo tiene en `bookings` un
contador de reprogramaciones y dos marcas, "cancelación tardía" y "reprogramación tardía". Las tres
dependen de datos que ya están en la base:

- `reschedule_count = count(*)` de `booking_reschedules` de la reserva.
- tardía ⇔ `hora del cambio > inicio de la cita − free_cancellation_window_minutes`, con la ventana de
  la política que congeló la reserva.

No rompen BCNF dentro de `bookings`, porque dependen de filas de otras tablas. Pero son redundancia entre
tablas, igual que la que quité en el Sprint 2, y pueden contradecir a la historia. Por eso se calculan
cuando se necesitan.

Los estados (`status`, `role`, `method`) son `varchar` con `CHECK` y no tablas de catálogo. Son listas
cerradas que cambian con el código y no con los datos, así que una tabla aparte sólo agregaría un join.

## 3. schema.sql

Está ordenado por dependencias: catálogos, identidad, organización, servicios y recursos, agendas,
reservas, notificaciones, reportes y auditoría. Después vienen las funciones y los triggers, los
procedimientos de las HU, los índices, los comentarios y, al final, la seguridad. Lo nuevo del Sprint 3
dice `[S3]` o `[S3 nueva]`, y cada decisión de normalización está comentada donde se toma.

Lo probé así:

- Contra un PostgreSQL 16 vacío corre sin errores y crea 35 tablas, 45 FK, 88 CHECK, 18 UNIQUE,
  6 EXCLUDE, 96 índices, 44 triggers y 5 procedimientos, con RLS activo en todas las tablas.
- Ninguna restricción, índice, trigger ni rutina se sale de la convención de nombres. Lo verifiqué
  contra el catálogo.
- Contra una base con los roles de Supabase (`anon`, `authenticated` y `auth.uid()`) crea además las
  políticas del Data API.
- Lo mismo en PostgreSQL 15 y 17, y en una base con los roles de Supabase.
- `seed.sql`, las 33 consultas, las 27 pruebas del Sprint 3 y las 51 del Sprint 2 corren encima. Cada
  prueba falla por la regla que le corresponde, y las partes de lo permitido pasan sin errores.
- `docker compose up` deja el contenedor `healthy` con todo cargado.

Al final del archivo hay una lista de lo que el esquema **no** garantiza. Por ejemplo, una sesión
insertada directamente, sin el procedimiento, no se revisa contra la agenda.

## 4. Triggers

Un trigger hace cumplir una regla de una HU en la base, de modo que se cumple aunque alguien escriba
directo en la tabla sin pasar por el backend. Todos son `for each row`. En PostgreSQL los `before` de
una tabla se disparan en orden alfabético y pueden rechazar o ajustar la fila antes de escribirla. Los
`after` se disparan con la fila ya escrita, y los uso para revisar lo que tuvo que pasar en la misma
transacción y para escribir en otra tabla.

### Los nuevos del Sprint 3

| Trigger | Tabla | Momento | Evento | HU | Propósito |
|---|---|---|---|---|---|
| `tg_bookings_anticipacion` | `bookings` | before | insert, update of `session_id` | 012, 014 | La cita cae dentro de la anticipación de la política, ni muy pronto ni muy lejos. Al crear se mide desde `created_at` y al reprogramar desde ahora |
| `tg_bookings_cruce_cliente` | `bookings` | before | insert, update of `session_id`, `status` | 012 | Un cliente no tiene dos reservas vivas que se crucen, aunque sean de proveedores distintos. Toma un candado por cliente para que dos pestañas no reserven a la vez |
| `tg_bookings_momento_del_estado` | `bookings` | before | update of `status` | 013, 016 | Una cita que ya empezó no se cancela, se cierra. La asistencia no se registra antes de que la cita empiece. Y la hora de la cancelación la pone la base, porque de ella sale si fue tardía |
| `tg_bookings_exige_historial` | `bookings` | after | update of `status` | 013, 016 | Cada cambio de estado deja su fila en `booking_status_changes` en la misma transacción, con el estado de origen y el de destino. Al cancelar, esa fila exige el motivo |
| `tg_booking_reschedules_reglas` | `booking_reschedules` | before | insert | 014 | Una reprogramación parte de la sesión actual de una reserva vigente, va al mismo servicio y sede, y no pasa el tope de la política. Bloquea la reserva para que dos reprogramaciones a la vez no se salten el tope |
| `tg_bookings_exige_reprogramacion` | `bookings` | after | update of `session_id` | 014 | Pasar una reserva a otra sesión exige su fila en `booking_reschedules` en la misma transacción. Así las reglas de arriba no se saltan con un `update` directo |
| `tg_bookings_avisos` | `bookings` | after | insert, update of `status`, `session_id` | 015 | Encola un aviso al crear, confirmar, cancelar o reprogramar, y programa los recordatorios del proveedor. Al cancelar o reprogramar descarta los pendientes y, si la reserva sigue viva, los recalcula |
| `tg_auditar_organization_booking_reminders` | `organization_booking_reminders` | after | insert, update, delete | 023 | Deja en `audit_log` quién cambió los recordatorios de un proveedor, igual que su política |

Dos de ellos, `tg_bookings_exige_historial` y `tg_bookings_exige_reprogramacion`, siguen la idea que en
el Sprint 2 usé para HU-003 con `tg_organizations_motivo`. El trigger no escribe la historia: exige
que exista. La fila tiene que estar fechada con `now()`, que en PostgreSQL es la hora de inicio de la
transacción, así que una fila vieja o una fechada a mano no sirve para autorizar el cambio. Por eso
son `after`: revisan después de escribir la reserva y, si falta la historia, deshacen todo. Los
procedimientos de la sección 5 escriben primero la historia y después el cambio.

### Los que ya estaban

Siguen igual. Ahora todos dicen a qué HU responden.

| Trigger | Tabla | Momento | Evento | HU | Propósito |
|---|---|---|---|---|---|
| `tg_bookings_reglas` | `bookings` | before | insert, update | 001 a 004 | Máquina de estados de la reserva, proveedor, servicio y sede activos, cliente no suspendido y verificado para confirmar, y cupo de la sesión con un candado por sesión |
| `tg_bookings_coherencia` | `bookings` | before | insert, update of `session_id`, `policy_id`, `currency_id` | 002, 004 | La política es del proveedor y estaba vigente al reservar, el precio va en la moneda del servicio, y una reserva sólo pasa a otra sesión del mismo servicio |
| `tg_sessions_libera_recursos` | `bookings` | after | update of `status`, `session_id` | 010, 013, 014 | Una sesión que se queda sin reservas vivas suelta sus recursos |
| `tg_sessions_coherencia` | `sessions` | before | update of `service_id`, `location_id`, `starts_at`, `ends_at` | 010, **014** | Una sesión no cambia de servicio, y si se mueve, sus recursos siguen en la sede y libres. **[S3]** Una sesión con reservas no se mueve. Si están vigentes, se reprograma cada reserva, para que no se salten la anticipación, el tope ni los recordatorios; si ya se cerraron, moverla reescribiría la historia |
| `tg_session_resources_reglas` | `session_resources` | before | insert, update of `session_id`, `resource_id` | 009, 010 | El recurso está activo, en la sede de la sesión y no lo ocupa otra sesión que se cruce |
| `tg_waitlist_entries_reserva` | `waitlist_entries` | before | insert, update of `booking_id`, `client_id`, `service_id`, `location_id` | 011, 012 | La reserva en que terminó una espera es del mismo cliente, servicio y sede |
| `tg_booking_reviews_completada` | `booking_reviews` | before | insert, update of `booking_id` | 016 | Sólo se califica una reserva atendida |
| `tg_clients_mayor_de_edad` | `clients` | before | insert, update of `birth_date` | 001 | El cliente tiene al menos 18 años |
| `tg_organizations_motivo` | `organizations` | after | update of `status` | 003 | Cambiar el estado de un proveedor exige el motivo en la misma transacción |
| `tg_service_locations_mismo_proveedor` | `service_locations` | before | insert, update | 004 | El servicio y la sede son del mismo proveedor |
| `tg_service_resource_requirements_mismo_proveedor` | `service_resource_requirements` | before | insert, update | 004, 009 | El servicio y el tipo de recurso son del mismo proveedor |
| `tg_resources_coherencia` | `resources` | before | insert, update of `resource_type_id`, `location_id` | 009 | El tipo y la sede son del mismo proveedor, y un recurso con sesiones o agenda no cambia de sede |
| `tg_locations_proveedor_inmutable`, `tg_services_proveedor_inmutable`, `tg_resource_types_proveedor_inmutable` | `locations`, `services`, `resource_types` | before | update of `organization_id` | 002, 004, 009 | El proveedor de una sede, un servicio o un tipo de recurso no cambia |
| `tg_agenda_services_en_sede` | `agenda_services` | before | insert, update | 006 | El servicio se presta en la sede de la agenda |
| `tg_agendas_servicios_en_sede` | `agendas` | before | update of `location_id`, `resource_id` | 006 | Si la agenda cambia de sede o de recurso, sus servicios se prestan en la nueva |
| `tg_service_locations_quita_de_agendas` | `service_locations` | after | delete, update | 004, 006 | Un servicio que deja de prestarse en una sede sale de las agendas de esa sede |
| `tg_auditar_*` (7) | `clients`, `organizations`, `organization_members`, `organization_policies`, `services`, `payments`, `booking_reviews` | after | insert, update, delete | 023 | Quién cambió qué fila, cuándo, y cada columna con su valor de antes y de después |
| `tg_*_updated_at` (11) | las tablas con `updated_at` | before | update | transversal | Mantiene `updated_at` |

### Comprobado

Las pruebas 1 a 17 de [`pruebas-sprint3.sql`](pruebas-sprint3.sql) hacen, cada una, lo que una regla
nueva prohíbe: reservar con muy poca o con demasiada anticipación, cruzar dos citas del mismo cliente,
cancelar una cita que ya empezó o sin motivo, registrar una asistencia antes de tiempo o sin decir si el
cliente llegó, cambiar un estado o una sesión con un `update` directo, mover la sesión en vez de
reprogramar la reserva, mover la de una cancelación ya cerrada para que deje de ser tardía, pasarse del
tope de reprogramaciones o reprogramar a otro servicio. Las diecisiete
terminan en `ERROR`, y el mensaje dice qué HU lo frenó:

```
ERROR:  HU-012: la cita se reserva con al menos 120 minutos de anticipación
ERROR:  HU-012: el cliente ya tiene otra reserva que se cruza con ese horario
ERROR:  HU-013: la cita ya empezó; se cierra como atendida o como inasistencia, no se cancela
ERROR:  HU-014: la reserva llegó al tope de su política: 1 reprogramación(es)
ERROR:  HU-014: pasar la reserva a otra sesión exige registrar la reprogramación en booking_reschedules
```

Los triggers que ya estaban los siguen probando las 51 pruebas de
[`pruebas-integridad.sql`](pruebas-integridad.sql). Comparé sus mensajes, uno por uno, con los del
Sprint 2, y son iguales: ningún trigger nuevo se adelanta a la regla que cada prueba quiere romper.

## 5. Procedimientos y funciones

Cada historia del ciclo de la reserva tiene su rutina en `schema.sql`. Uso tres prefijos:

- **`sp_`** para un **procedimiento**, que cambia datos y se llama con `call`. Devuelve su resultado en
  parámetros `out`, y en el `call` se pasa `null` en el lugar de cada uno.
- **`fn_`** para una **función** de consulta, que se usa en un `select` como si fuera una tabla.
- **`f_`** para una **auxiliar** que usan las demás.

Todas son `security invoker`: corren con los permisos de quien las llama, y los triggers revisan cada
fila igual que si la aplicación escribiera directo. Un procedimiento no se salta ninguna regla: se
limita a juntar en una transacción los pasos que una HU necesita, en el orden correcto.

| Rutina | Tipo | HU | Parámetros | Resultado |
|---|---|---|---|---|
| `sp_crear_reserva` | procedimiento | 012 | `p_client_id uuid`, `p_service_id uuid`, `p_location_id uuid`, `p_starts_at timestamptz`, `p_attendees integer` | `o_booking_id uuid`, `o_code varchar`, `o_status varchar` |
| `sp_cancelar_reserva` | procedimiento | 013 | `p_booking_id uuid`, `p_reason varchar`, `p_cancelled_by uuid` | `o_late boolean`: si fue tardía |
| `sp_reprogramar_reserva` | procedimiento | 014 | `p_booking_id uuid`, `p_starts_at timestamptz`, `p_reason varchar`, `p_rescheduled_by uuid` | `o_session_id uuid`, `o_remaining integer`: reprogramaciones que quedan |
| `sp_registrar_asistencia` | procedimiento | 016 | `p_booking_id uuid`, `p_attended boolean`, `p_recorded_by uuid` | `o_status varchar`: `COMPLETED` o `NO_SHOW` |
| `sp_cerrar_reservas_vencidas` | procedimiento | 016 | ninguno | `o_closed integer`: cuántas cerró |
| `fn_franjas_disponibles` | función | 008, 011 | `p_service_id uuid`, `p_location_id uuid`, `p_fecha date` | tabla `(starts_at, ends_at, free_places)` |
| `fn_historial_cliente` | función | 017 | `p_client_id uuid` | tabla con una fila por reserva: código, servicio, proveedor, sede, hora, estado, precio, pagado y reprogramaciones |
| `fn_comprobante_reserva` | función | 017, 018 | `p_code varchar` | una fila con los datos del comprobante |
| `fn_reporte_ocupacion` | función | 019 | `p_organization_id uuid`, `p_from date`, `p_to date` | tabla `(location, resource, available_minutes, booked_minutes, sessions, occupancy_pct)` |
| `f_sesion_para_reserva` | auxiliar | 010, 012, 014 | `p_service_id`, `p_location_id`, `p_starts_at` | `uuid` de la sesión |
| `f_recurso_atiende` | auxiliar | 008 a 010 | `p_resource_id`, `p_inicio`, `p_fin` | `boolean` |
| `f_codigo_reserva` | auxiliar | 018 | ninguno | `varchar`: el código, como `DEFAULT` de `bookings.code` |

Del Sprint 2 siguen `fn_calcular_ocupacion(p_dia date)`, que llena el resumen diario de HU-019, y
`f_sin_tildes(texto)`, la búsqueda de HU-005.

**Cómo probar los ejemplos.** Cada rutina tiene abajo un ejemplo de llamada con el resultado que da.
Los ejemplos se pueden pegar tal cual, en el orden en que aparecen, en un `psql` sobre la base recién
levantada con `docker compose up` (o después de correr `seed.sql`). Van dentro de una transacción que se
deshace al final, para que el seed quede igual y las consultas y las pruebas sigan dando lo que dicen. La
zona horaria se fija porque las fechas del seed son las de Medellín:

```sql
set timezone = 'America/Bogota';
begin;
```

Los códigos de reserva y los `uuid` que se generan cambian en cada carga del seed.

### `sp_crear_reserva` · HU-012

Crea una reserva en una franja. Toma la política vigente del proveedor, pacta el precio (precio del
servicio × asistentes) en la moneda del servicio, y deja la reserva `CONFIRMED` si el proveedor no
confirma a mano y el cliente ya verificó su correo. Si no, la deja `RESERVED`. Por dentro,
`f_sesion_para_reserva` revisa que la hora sea una de las franjas de `fn_franjas_disponibles`. Si ya hay
una sesión con reservas a esa hora (un taller con cupo), la reserva entra a ella; si no, abre una sesión
y le asigna los recursos libres que el servicio exige (HU-010). Al final escribe el primer estado en la
historia, y `tg_bookings_avisos` encola el aviso y los recordatorios.

Camilo reserva un corte en Envigado dentro de cuatro días a las 10:00. La barbería no confirma a mano y
Camilo ya verificó su correo, así que queda confirmada:

```sql
call sp_crear_reserva('44444444-0000-0000-0000-000000000003',   -- Camilo
                      'aaaa0000-0000-0000-0000-000000000001',   -- Corte clásico
                      '88888888-0000-0000-0000-000000000002',   -- Sede Envigado
                      current_date + 4 + time '10:00', 1, null, null, null);
```
```
             o_booking_id             |       o_code       | o_status
--------------------------------------+--------------------+-----------
 4753093b-f2e9-48e4-91df-25b1feae3be9 | RSV-9F22-0E89-78DC | CONFIRMED
```

### `sp_cancelar_reserva` · HU-013

Cancela una reserva vigente con su motivo. Escribe primero la historia, con el motivo, y después cambia el
estado, para que `tg_bookings_exige_historial` encuentre su fila. Devuelve si la cancelación fue
tardía, es decir, dentro de la ventana en que la política ya no la deja gratis. Ese dato no se guarda,
se calcula.

Mariana cancela su limpieza dental de mañana. La clínica da 48 horas para cancelar gratis, así que es
tardía:

```sql
call sp_cancelar_reserva('dddd0000-0000-0000-0000-000000000004', 'Viaje imprevisto',
                         '44444444-0000-0000-0000-000000000001', null);
```
```
 o_late
--------
 t
```

### `sp_reprogramar_reserva` · HU-014

Pasa una reserva a otra hora del mismo servicio y la misma sede. Bloquea la reserva, busca o abre la
sesión de destino con sus recursos, escribe la reprogramación en `booking_reschedules` y cambia la
sesión. La sesión vieja suelta sus recursos si se queda sin reservas. Devuelve la sesión nueva y cuántas
reprogramaciones le quedan según la política.

Laura pasa su barba, que chocaba con el mantenimiento de la silla 2 (consulta 20), a dentro de cuatro
días a las 11:00. Su política deja una reprogramación, así que no le queda ninguna:

```sql
call sp_reprogramar_reserva('dddd0000-0000-0000-0000-000000000002',
                            current_date + 4 + time '11:00',
                            'La silla entra a mantenimiento',
                            '44444444-0000-0000-0000-000000000002', null, null);
```
```
             o_session_id             | o_remaining
--------------------------------------+-------------
 5248440f-7a66-45b9-93f5-6d31ea0f14db |           0
```

### `sp_registrar_asistencia` · HU-016

Registra si el cliente asistió. Una reserva confirmada queda `COMPLETED` (`p_attended = true`) o
`NO_SHOW`. Una reserva que nunca se confirmó sólo puede quedar como inasistencia. La cita tiene que
haber empezado.

La cita de Camilo en Envigado está en curso (el seed la pone en la media hora en que se carga) y
llegó:

```sql
call sp_registrar_asistencia('dddd0000-0000-0000-0000-000000000018', true,
                             '99999999-0000-0000-0000-000000000002', null);
```
```
 o_status
-----------
 COMPLETED
```

### `sp_cerrar_reservas_vencidas` · HU-016

Cierra las reservas que siguen vivas cuando ya pasaron, desde el final de la cita, las horas que da la
política (`auto_close_delay_hours`). Una confirmada se cierra como diga `default_closure_status`. Una que
nunca se confirmó se cierra como inasistencia. Cada cierre deja su historia con el motivo y sin persona
(`changed_by` nulo). Usa `for update skip locked` para no esperar a las reservas que alguien está
tocando. Está pensado para un job (pg_cron en Supabase) o para el backend.

El seed ya lo corrió y cerró las dos citas vencidas que había (consulta 29), así que sobre el seed
recién cargado no encuentra ninguna. Correrlo otra vez no cambia nada:

```sql
call sp_cerrar_reservas_vencidas(null);
```
```
 o_closed
----------
        0
```

### `fn_calcular_ocupacion` · HU-019 (del Sprint 2)

Llena `resource_occupancy_daily` para un día: por cada recurso activo, los minutos que su agenda
ofrecía menos las excepciones, y los minutos y sesiones que se ocuparon. Se puede repetir, porque
reescribe el día. La corre un job diario, por eso sólo rol_admin tiene `EXECUTE`. Devuelve cuántas filas
escribió.

```sql
select fn_calcular_ocupacion(current_date - 1);
```
```
 fn_calcular_ocupacion
-----------------------
                     7
```

Son los siete recursos activos del seed; la Unidad B está retirada y no cuenta.

### `fn_franjas_disponibles` · HU-008 y HU-011

Las franjas en que se puede reservar un servicio en una sede un día dado, con los cupos que quedan. Una
franja sale de un bloque de alguna agenda de la sede, o de uno de sus recursos, que ofrezca el servicio,
cada `slot_minutes` y sin pisar una excepción de esa agenda (HU-007). Se queda si está dentro de la
anticipación de la política y si le quedan cupos. Cuando hay que abrir la sesión, además, tiene que haber
recursos de cada tipo exigido que puedan atender: activos, libres, sin mantenimiento y dentro de su
propia agenda (`f_recurso_atiende`).

```sql
select * from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001',
                                     '88888888-0000-0000-0000-000000000001',
                                     current_date + 4) limit 3;
```
```
       starts_at        |        ends_at         | free_places
------------------------+------------------------+-------------
 2026-11-29 08:00:00-05 | 2026-11-29 08:30:00-05 |           1
 2026-11-29 08:30:00-05 | 2026-11-29 09:00:00-05 |           1
 2026-11-29 09:00:00-05 | 2026-11-29 09:30:00-05 |           1
```

En el festivo de la Sede Poblado devuelve cero filas, y un taller lleno no aparece.

### `fn_historial_cliente` · HU-017

El historial de reservas de un cliente, de la más reciente a la más vieja, con lo que pagó en la moneda
pactada y cuántas veces la reprogramó.

```sql
select code, service, starts_at, status, total_price, paid_amount, reschedules
from fn_historial_cliente('44444444-0000-0000-0000-000000000004') limit 2;
```
```
        code        |      service       |       starts_at        |  status   | total_price | paid_amount | reschedules
--------------------+--------------------+------------------------+-----------+-------------+-------------+-------------
 RSV-2492-DB77-DC8C | Taller de barbería | 2026-11-30 09:00:00-05 | CONFIRMED |    60000.00 |           0 |           0
 RSV-4D01-E9A9-7F9A | Corte clásico      | 2026-11-28 09:00:00-05 | CONFIRMED |    35000.00 |           0 |           0
```

### `fn_comprobante_reserva` · HU-017 y HU-018

Los datos del comprobante de una reserva, buscada por su código: cliente y documento, proveedor e
identificación, sede, servicio, hora local, precio y el pago que cuenta. El pago vigente o el
reembolsado va antes que un intento fallido. El backend arma el PDF con esta fila.

El comprobante de la reserva que Mariana canceló arriba. Su código se busca por el `uuid` porque
cambia en cada carga:

```sql
\x on
select code, status, client_name, provider, provider_identification, service,
       local_start, total_price, currency, payment_method, payment_status
from fn_comprobante_reserva((select code from bookings where id = 'dddd0000-0000-0000-0000-000000000004'));
\x off
```
```
-[ RECORD 1 ]-----------+--------------------
code                    | RSV-B01D-C6FE-79AD
status                  | CANCELLED
client_name             | Mariana Ospina
provider                | Clínica Dental Sur
provider_identification | NIT 901234567-2
service                 | Limpieza dental
local_start             | 2026-11-26 09:00:00
total_price             | 90000.00
currency                | COP
payment_method          | CARD
payment_status          | PAID
```

Esa reserva tuvo un primer pago rechazado y un segundo aprobado; el comprobante muestra el aprobado.

### `fn_reporte_ocupacion` · HU-019

La ocupación de los recursos de un proveedor entre dos fechas, leída del resumen diario que llena
`fn_calcular_ocupacion`. El porcentaje es nulo si el recurso no tuvo horas disponibles.

```sql
select * from fn_reporte_ocupacion('66666666-0000-0000-0000-000000000001', current_date - 30, current_date);
```
```
   location    |    resource     | available_minutes | booked_minutes | sessions | occupancy_pct
---------------+-----------------+-------------------+----------------+----------+---------------
 Sede Envigado | Silla única     |             16200 |            120 |        4 |           0.7
 Sede Poblado  | Salón principal |             16200 |              0 |        0 |           0.0
 Sede Poblado  | Silla 1         |             16200 |             30 |        1 |           0.2
 Sede Poblado  | Silla 2         |             16200 |             90 |        2 |           0.6
 Sede Poblado  | Silla 3         |             15600 |             30 |        1 |           0.2
 Sede Poblado  | Silla 4         |             16200 |              0 |        0 |           0.0
```

Y al final se deshace todo:

```sql
rollback;
```

### Comprobado

La parte 2 de [`pruebas-sprint3.sql`](pruebas-sprint3.sql) recorre con `rol_app` el ciclo completo de
una reserva: consulta las franjas, reserva la primera, ve el aviso y los dos recordatorios encolados, la
reprograma, la cancela, registra la asistencia de otra cita que está en curso, corre el cierre automático
y consulta el historial, el comprobante y el reporte. Todo pasa sin un error, y al final se deshace. Las
pruebas 4, 5, 8, 9, 13, 14 y 16 llaman a los procedimientos con datos que su HU no permite, y cada una
termina en el error de esa HU. Los ejemplos de esta sección los corrí uno tras otro sobre el seed recién
cargado, y los resultados de arriba son los que dieron.

## 6. Consultas

Las 33 están en [`consultas.sql`](consultas.sql) y, completas, en los tres desplegables de abajo. Cada
una dice la pregunta que responde, y todas devuelven filas con `seed.sql`. El archivo usa `\echo` para
titular cada resultado, así que se corre con `psql -f` y no en el editor SQL de Supabase. Empieza
con `set timezone = 'America/Bogota'`, porque los negocios son de Medellín y sin eso las fechas se
agruparían en UTC, que es la zona del servidor en Supabase. Las del Sprint 1 y el Sprint 2 corren sin
cambios sobre el esquema del Sprint 3; las nueve nuevas responden a una HU de este sprint cada una.

| # | Pregunta | Cómo | HU |
|---|---|---|---|
| **Sprint 1** | | | |
| 1 | ¿Qué servicios puede reservar un cliente en Medellín, en qué sede y a qué precio? | join de 6 tablas, filtros | 002, 004 |
| 2 | ¿Cuál es la ocupación por sede y semana: reservas, asistentes e ingresos? | agregación, `date_trunc` | caso |
| 3 | ¿Qué servicios no puede prestar una sede por falta de recursos? | `left join`, `having` | 004 |
| 4 | ¿Cuáles son los servicios más reservados de cada organización, con empates? | `rank()` | caso |
| 5 | Si se suspende un proveedor, ¿qué reservas futuras quedan afectadas? | join, subconsulta | 003 |
| 6 | ¿Qué agenda tiene cada recurso pasado mañana y cuánta carga lleva? | `left join`, agregación | 006 |
| 7 | ¿Qué proveedores llevan más tiempo esperando aprobación? | filtro, antigüedad | 003 |
| 8 | ¿Está bloqueada una cuenta por intentos fallidos? | agregación con ventana de tiempo | 021 |
| 9 | ¿Qué clientes llevan más de 24 h sin verificar el correo? | join, filtro de tiempo | 001 |
| 10 | ¿Qué condiciones de cancelación rigen para cada reserva? | join, `case` | 002 |
| 11 | ¿El correo, el documento o el NIT ya están registrados? | `exists` | 001, 002 |
| 12 | ¿Qué clientes se registraron y nunca han reservado? | `not exists` correlacionado | 001 |
| 13 | ¿Qué servicios se prestan en una sede y no en otra? | diferencia, `except` | 004 |
| 14 | ¿Qué sedes ofrecen todos los servicios activos de su organización? | división, doble negación | 004 |
| **Sprint 2** | | | |
| 15 | ¿Qué porcentaje de su horario estuvo ocupado cada recurso en los últimos 30 días? | join, agregación, `having` | caso |
| 16 | ¿Qué servicios tienen mejor calificación y con cuántas reseñas? | join de 5 tablas, `avg` | caso |
| 17 | ¿Quién sigue en lista de espera para cada servicio y día, y en qué turno? | join, `row_number()` | — |
| 18 | ¿Cuánto cobró, cuánto devolvió y cuánto le quedó a cada proveedor por mes? | `with`, `union all`, agregación | — |
| 19 | ¿Qué agendas cierran o recortan su horario en las próximas dos semanas? | `left join`, filtro de fechas | 006 |
| 20 | ¿Qué reservas vivas chocan con un mantenimiento programado? | join por solapamiento de rangos `&&` | 009 |
| 21 | ¿Qué servicios encuentra quien busca "clasico", sin tilde? | `f_sin_tildes`, `like` | 005 |
| 22 | ¿Qué reservas atendidas en los últimos 30 días no tienen reseña? | antijoin, `not exists` | — |
| 23 | ¿Quién cambió datos sensibles en la última semana y qué cambió? | join con el detalle por columna | — |
| 24 | ¿Cuántas reservas e ingresos dejó cada servicio de un proveedor en el mes? | join de 3 tablas, agregación | caso |
| **Sprint 3** | | | |
| 25 | ¿Qué ve el cliente cuando busca su reserva por el código? | join de 6 tablas por clave candidata | 018 |
| 26 | ¿Qué reservas se reprogramaron, de qué hora a cuál, si fue tardía y cuántas les quedan? | dos joins a `sessions`, `count() over` | 014 |
| 27 | ¿Cuántas cancelaciones tuvo cada proveedor en 30 días y cuántas fueron tardías? | `count() filter`, dato derivado | 013 |
| 28 | ¿Qué porcentaje de inasistencia tiene cada servicio? | `count() filter`, agregación | 016 |
| 29 | ¿Qué reservas cerró el sistema solo, y cómo quedaron? | join sobre la historia de estados | 016 |
| 30 | ¿Qué recordatorios salen en las próximas 48 horas, a quién y por qué canal? | join de 5 tablas, filtro de tiempo | 015 |
| 31 | ¿Qué reservas esperan confirmación, y qué les falta? | join, `case` | 012 |
| 32 | ¿Qué días y a qué horas se concentra la demanda de cada proveedor? | agregación por día y hora local | 020 |
| 33 | ¿Cuántas franjas libres tiene mañana cada servicio en cada sede? | `left join lateral` a una función | 008, 011 |

La 26 y la 27 calculan si un cambio fue tardío en vez de leerlo de una columna: es la decisión de
normalización de este sprint puesta a trabajar. La 33 usa `fn_franjas_disponibles` como si fuera una
tabla, una vez por cada servicio y sede.

La 24 es la que analizo en el documento de almacenamiento. La 20 muestra para qué sirve tener los
mantenimientos en su propia tabla: cruza rangos de tiempo con `&&` y encuentra la reserva que hay que
mover antes de que llegue el cliente. La 15 lee el resumen diario de ocupación en vez de recorrer las
sesiones.

<details>
<summary><b>Las 14 consultas del Sprint 1</b></summary>

**1.** ¿Qué servicios puede reservar un cliente en Medellín, en qué sede y a qué precio? Es la consulta del catálogo público, y aplica la regla de HU-002: un proveedor pendiente no es visible.

```sql
select o.name              as organizacion,
       s.name              as servicio,
       l.name              as sede,
       s.duration_minutes  as minutos,
       s.price,
       cur.code            as moneda,
       s.customer_capacity as cupo
from services s
    inner join organizations     o   on o.id   = s.organization_id
    inner join service_locations sl  on sl.service_id = s.id
    inner join locations         l   on l.id   = sl.location_id
    inner join cities            c   on c.id   = l.city_id
    inner join currencies        cur on cur.id = s.currency_id
where c.name   = 'Medellín'
  and s.status = 'ACTIVE'
  and l.status = 'ACTIVE'
  and o.status = 'ACTIVE'
order by o.name, s.name;
```

**2.** ¿Cuál es la ocupación por sede y semana? Es el reporte de uso que pide el enunciado del caso.

```sql
select l.name                                 as sede,
       date_trunc('week', se.starts_at)::date as semana,
       count(*)                               as reservas,
       sum(b.attendees)                       as asistentes,
       sum(b.total_price)                     as ingresos
from bookings b
    inner join sessions  se on se.id = b.session_id
    inner join locations l  on l.id  = se.location_id
where b.status in ('CONFIRMED', 'COMPLETED')
group by l.name, date_trunc('week', se.starts_at)
order by semana, sede;
```

**3.** ¿Qué servicios no puede prestar una sede porque no tiene recursos suficientes? Detecta servicios publicados que en la práctica no se pueden ejecutar ahí.

```sql
select o.name                as organizacion,
       s.name                as servicio,
       l.name                as sede,
       rt.name               as tipo_de_recurso,
       srr.quantity_required as requiere,
       count(r.id)           as disponibles
from services s
    inner join organizations                  o   on o.id  = s.organization_id
    inner join service_locations              sl  on sl.service_id = s.id
    inner join locations                      l   on l.id  = sl.location_id
    inner join service_resource_requirements  srr on srr.service_id = s.id
    inner join resource_types                 rt  on rt.id = srr.resource_type_id
    left  join resources                      r   on r.resource_type_id = rt.id
                                                 and r.location_id      = l.id
                                                 and r.status           = 'ACTIVE'
group by o.name, s.name, l.name, rt.name, srr.quantity_required
having count(r.id) < srr.quantity_required
order by o.name, s.name, l.name;
```

**4.** ¿Cuáles son los servicios más reservados de cada organización? Con rank() y no row_number() para que los empates compartan puesto.

```sql
select organizacion, servicio, reservas, posicion
from (
    select o.name      as organizacion,
           s.name      as servicio,
           count(b.id) as reservas,
           rank() over (partition by o.id order by count(b.id) desc) as posicion
    from services s
        inner join organizations o  on o.id = s.organization_id
        left  join sessions      se on se.service_id = s.id
        left  join bookings      b  on b.session_id = se.id
                                   and b.status in ('CONFIRMED', 'COMPLETED')
    group by o.id, o.name, s.name
) ranking
where posicion <= 3
order by organizacion, posicion, servicio;
```

**5.** Si se suspende un proveedor, ¿qué reservas futuras quedan afectadas? HU-003 pide ese informe antes de confirmar la suspensión.

```sql
select b.id        as reserva,
       c.full_name as cliente,
       c.email,
       c.phone,
       s.name      as servicio,
       l.name      as sede,
       se.starts_at,
       b.status
from bookings b
    inner join sessions  se on se.id = b.session_id
    inner join services  s  on s.id  = se.service_id
    inner join clients   c  on c.id  = b.client_id
    inner join locations l  on l.id  = se.location_id
where s.organization_id = (select id from organizations where identification_type = 'NIT' and identification_number = '900123456-1')
  and se.starts_at >= now()
  and b.status in ('RESERVED', 'CONFIRMED')
order by se.starts_at;
```

**6.** ¿Qué agenda tiene cada recurso pasado mañana y cuánta carga lleva? El left join es lo que deja ver también los recursos libres. Cuenta sesiones vivas dentro de cada bloque: el taller ocupa el salón una vez aunque tenga dos reservas, y una sesión de la mañana no se cuenta en el bloque de la tarde.

```sql
select l.name         as sede,
       r.name         as recurso,
       sch.start_time as abre,
       sch.end_time   as cierra,
       count(se.id)   as sesiones
from schedules sch
    inner join agendas   a on a.id = sch.agenda_id
                          and current_date + 2 >= a.valid_from
                          and (a.valid_until is null or current_date + 2 <= a.valid_until)
    inner join resources r on r.id = a.resource_id
    inner join locations l on l.id = r.location_id
    left  join (session_resources sr
                inner join sessions se on se.id = sr.session_id
                                      and se.starts_at::date = current_date + 2
                                      and exists (select 1 from bookings b
                                                   where b.session_id = se.id
                                                     and b.status in ('RESERVED', 'CONFIRMED')))
               on  sr.resource_id = r.id
               and se.starts_at::time >= sch.start_time
               and se.starts_at::time <  sch.end_time
where sch.day_of_week = extract(isodow from current_date + 2)
  and sch.active
group by l.name, r.name, sch.start_time, sch.end_time
order by l.name, r.name;
```

**7.** ¿Qué proveedores llevan más tiempo esperando aprobación? Es la cola de trabajo del administrador (HU-003).

```sql
select o.name                            as organizacion,
       o.identification_type,
       o.identification_number,
       oc.name                           as categoria,
       o.contact_email,
       o.created_at::date                as solicitado_el,
       current_date - o.created_at::date as dias_esperando
from organizations o
    inner join organization_categories oc on oc.id = o.category_id
where o.status = 'PENDING_APPROVAL'
order by dias_esperando desc, o.name;
```

**8.** ¿Está bloqueada una cuenta por intentos fallidos? La política es cinco fallos en quince minutos (HU-021).

```sql
select email,
       count(*)          as fallos_recientes,
       max(attempted_at) as ultimo_intento,
       count(*) >= 5     as bloqueada
from login_attempts
where success = false
  and attempted_at > now() - interval '15 minutes'
group by email
order by fallos_recientes desc;
```

**9.** ¿Qué clientes llevan más de 24 horas sin verificar el correo? Es la lista a la que hay que reenviarles el enlace (HU-001).

```sql
select c.id,
       c.full_name,
       c.email,
       ci.name               as ciudad,
       c.created_at,
       now() - c.created_at  as lleva_esperando
from clients c
    inner join cities ci on ci.id = c.city_id
where c.status = 'PENDING_VERIFICATION'
  and c.created_at < now() - interval '24 hours'
order by c.created_at;
```

**10.** ¿Qué condiciones de cancelación rigen para cada reserva? Como cada reserva apunta a la versión de política que regía al crearse, dos reservas del mismo negocio salen con ventanas distintas. Es la prueba de que la regla de HU-002 está resuelta en el modelo.

```sql
select o.name                              as organizacion,
       se.starts_at,
       b.status,
       op.version                          as version_politica,
       op.free_cancellation_window_minutes as minutos_cancelacion_gratis,
       case when op.replaced_at is null
            then 'vigente'
            else 'histórica' end           as estado_de_la_politica
from bookings b
    inner join sessions              se on se.id = b.session_id
    inner join organization_policies op on op.id = b.policy_id
    inner join organizations         o  on o.id  = op.organization_id
order by o.name, se.starts_at;
```

**11.** ¿El correo, el documento o el NIT ya están registrados? Es la validación previa al registro, en una sola ida a la base.

```sql
select exists (select 1 from clients       where lower(email) = lower('laura@example.com')) as correo_ya_registrado,
       exists (select 1 from clients       where document     = '1020334455')               as documento_ya_registrado,
       exists (select 1 from organizations where identification_type = 'NIT'
                                      and identification_number = '900123456-1')    as nit_ya_registrado;
```

**12.** ¿Qué clientes se registraron y nunca han reservado? Subconsulta correlacionada con el operador de existencia.

```sql
select c.id, c.full_name, c.email, ci.name as ciudad, c.status
from   clients c
       inner join cities ci on ci.id = c.city_id
where  not exists (select 1
                   from   bookings b
                   where  b.client_id = c.id)
order by c.full_name;
```

**13.** ¿Qué servicios se prestan en la Sede Poblado pero no en Envigado? Operador de diferencia del álgebra relacional.

```sql
select s.name as servicio
from   service_locations sl
       inner join services  s on s.id = sl.service_id
       inner join locations l on l.id = sl.location_id
where  l.name = 'Sede Poblado'
except
select s.name
from   service_locations sl
       inner join services  s on s.id = sl.service_id
       inner join locations l on l.id = sl.location_id
where  l.name = 'Sede Envigado'
order by servicio;
```

**14.** ¿Qué sedes ofrecen TODOS los servicios activos de su organización? Es el operador de división del álgebra relacional, expresado con la doble negación: no existe un servicio activo de la organización que no se preste en esa sede.

```sql
select o.name as organizacion, l.name as sede
from   locations l
       inner join organizations o on o.id = l.organization_id
where  l.status = 'ACTIVE'
  and  not exists (select 1
                   from   services s
                   where  s.organization_id = l.organization_id
                     and  s.status = 'ACTIVE'
                     and  not exists (select 1
                                      from   service_locations sl
                                      where  sl.service_id  = s.id
                                        and  sl.location_id = l.id))
order by o.name, l.name;
```

</details>

<details>
<summary><b>Las 10 consultas del Sprint 2</b></summary>

**15.** ¿Qué porcentaje de su horario estuvo ocupado cada recurso en los últimos 30 días? Es el reporte de ocupación del caso. Lee el resumen diario, no las reservas. Ordenado del más al menos usado.

```sql
select l.name                    as sede,
       r.name                    as recurso,
       sum(o.available_minutes)  as minutos_disponibles,
       sum(o.booked_minutes)     as minutos_ocupados,
       round(100.0 * sum(o.booked_minutes) / nullif(sum(o.available_minutes), 0), 1) as porcentaje
from resource_occupancy_daily o
    inner join resources r on r.id = o.resource_id
    inner join locations l on l.id = r.location_id
where o.occupancy_date between current_date - 30 and current_date - 1
group by l.name, r.name
having sum(o.available_minutes) > 0
order by porcentaje desc, sede, recurso;
```

**16.** ¿Qué servicios tienen mejor calificación y con cuántas reseñas? El promedio sale de la reserva: la reseña no copia el servicio.

```sql
select o.name                  as organizacion,
       s.name                  as servicio,
       count(*)                as resenas,
       round(avg(br.rating), 2) as promedio,
       min(br.rating)          as peor,
       max(br.rating)          as mejor
from booking_reviews br
    inner join bookings      b  on b.id  = br.booking_id
    inner join sessions      se on se.id = b.session_id
    inner join services      s  on s.id  = se.service_id
    inner join organizations o  on o.id  = s.organization_id
group by o.name, s.name
order by promedio desc, resenas desc;
```

**17.** ¿Quién sigue en lista de espera para cada servicio y día, y en qué turno? El turno es el orden de llegada.

```sql
select s.name          as servicio,
       l.name          as sede,
       w.desired_date  as dia,
       row_number() over (partition by w.service_id, w.location_id, w.desired_date
                          order by w.created_at) as turno,
       c.full_name     as cliente,
       w.attendees     as cupos_pedidos
from waitlist_entries w
    inner join clients   c on c.id = w.client_id
    inner join services  s on s.id = w.service_id
    inner join locations l on l.id = w.location_id
where w.status = 'WAITING'
  and w.desired_date >= current_date
order by servicio, sede, dia, turno;
```

**18.** ¿Cuánto cobró, cuánto devolvió y cuánto le quedó a cada proveedor por mes? Cada pago cuenta en el mes en que se cobró, y su reembolso en el mes en que se devolvió, que puede ser otro. Los fallidos y pendientes no cuentan. Une los dos movimientos con union all.

```sql
with movimientos as (
    select s.organization_id, p.currency_id,
           date_trunc('month', p.paid_at) as mes, p.amount as cobrado, 0 as devuelto
    from payments p
        inner join bookings b  on b.id  = p.booking_id
        inner join sessions se on se.id = b.session_id
        inner join services s  on s.id  = se.service_id
    where p.status in ('PAID', 'REFUNDED')
    union all
    select s.organization_id, p.currency_id,
           date_trunc('month', p.refunded_at), 0, p.amount
    from payments p
        inner join bookings b  on b.id  = p.booking_id
        inner join sessions se on se.id = b.session_id
        inner join services s  on s.id  = se.service_id
    where p.status = 'REFUNDED'
)
select o.name                          as organizacion,
       m.mes::date                     as mes,
       cur.code                        as moneda,
       sum(m.cobrado)                  as cobrado,
       sum(m.devuelto)                 as devuelto,
       sum(m.cobrado) - sum(m.devuelto) as neto
from movimientos m
    inner join organizations o   on o.id   = m.organization_id
    inner join currencies    cur on cur.id = m.currency_id
group by o.name, m.mes, cur.code
order by organizacion, mes;
```

**19.** ¿Qué agendas cierran o recortan su horario en las próximas dos semanas? Sirve para avisar a los clientes con reservas esos días. La sede es la de la agenda, si es de toda la sede, o la de su recurso.

```sql
select e.exception_date                                   as dia,
       l.name                                             as sede,
       coalesce(r.name, 'Toda la sede')                   as recurso,
       coalesce(e.start_time::text || ' - ' || e.end_time::text, 'Todo el día') as franja,
       e.reason                                           as motivo
from agenda_exceptions e
    inner join agendas   a on a.id = e.agenda_id
    left  join resources r on r.id = a.resource_id
    inner join locations l on l.id = coalesce(a.location_id, r.location_id)
where e.exception_date between current_date and current_date + 14
order by dia, sede, recurso;
```

**20.** ¿Qué reservas vivas chocan con un mantenimiento programado? Son las que hay que mover antes de que el cliente llegue (HU-009).

```sql
select r.name       as recurso,
       m.starts_at  as mantenimiento_desde,
       m.ends_at    as mantenimiento_hasta,
       m.reason     as motivo,
       c.full_name  as cliente,
       se.starts_at as reserva
from resource_maintenances m
    inner join resources         r  on r.id = m.resource_id
    inner join session_resources sr on sr.resource_id = m.resource_id
    inner join sessions          se on se.id = sr.session_id
                                   and tstzrange(se.starts_at, se.ends_at) && tstzrange(m.starts_at, m.ends_at)
    inner join bookings          b  on b.session_id = se.id
                                   and b.status in ('RESERVED', 'CONFIRMED')
    inner join clients           c  on c.id = b.client_id
order by se.starts_at;
```

**21.** ¿Qué servicios encuentra quien busca "clasico", sin tilde? Es la búsqueda pública de HU-005, que no distingue mayúsculas ni tildes.

```sql
select o.name as organizacion, s.name as servicio, s.price
from services s
    inner join organizations o on o.id = s.organization_id
where s.status = 'ACTIVE'
  and o.status = 'ACTIVE'
  and (f_sin_tildes(s.name)        like '%' || f_sin_tildes('clasico') || '%'
    or f_sin_tildes(s.description) like '%' || f_sin_tildes('clasico') || '%'
    or f_sin_tildes(o.name)        like '%' || f_sin_tildes('clasico') || '%')
order by o.name, s.name;
```

**22.** ¿Qué reservas atendidas en los últimos 30 días no tienen reseña? Es a quién pedirle que califique. Antijoin con not exists.

```sql
select c.full_name  as cliente,
       c.email,
       s.name       as servicio,
       se.starts_at as atendida
from bookings b
    inner join sessions se on se.id = b.session_id
    inner join clients  c  on c.id  = b.client_id
    inner join services s  on s.id  = se.service_id
where b.status = 'COMPLETED'
  and se.starts_at >= now() - interval '30 days'
  and not exists (select 1 from booking_reviews br where br.booking_id = b.id)
order by se.starts_at;
```

**23.** ¿Quién cambió datos sensibles en la última semana y qué cambió? Consulta del administrador sobre la auditoría: cada columna modificada, con su valor de antes y el de después.

```sql
select a.changed_at,
       a.table_name,
       a.record_id,
       a.db_user,
       a.app_user_id,
       ch.column_name as columna,
       ch.old_value   as antes,
       ch.new_value   as despues
from audit_log a
    inner join audit_log_changes ch on ch.audit_log_id = a.id
where a.operation = 'UPDATE'
  and a.changed_at >= now() - interval '7 days'
order by a.changed_at desc, ch.column_name;
```

**24.** ¿Cuántas reservas e ingresos dejó cada servicio de un proveedor en el mes? Es la consulta que se analiza en docs/analisis-almacenamiento.md (costo y optimización).

```sql
select s.name             as servicio,
       count(*)           as reservas,
       sum(b.total_price) as ingresos
from services s
    inner join sessions se on se.service_id = s.id
    inner join bookings b  on b.session_id  = se.id
where s.organization_id = '66666666-0000-0000-0000-000000000001'
  and se.starts_at >= date_trunc('month', now())
  and se.starts_at <  date_trunc('month', now()) + interval '1 month'
  and b.status in ('CONFIRMED', 'COMPLETED')
group by s.name
order by ingresos desc;
```

</details>

<details>
<summary><b>Las 9 consultas del Sprint 3</b></summary>

**25.** ¿Qué ve el cliente cuando busca su reserva por el código? Es la consulta de HU-018: el código es una clave candidata de bookings, así que devuelve una sola fila. La hora va en la zona de la sede.

```sql
select b.code,
       c.full_name                                         as cliente,
       s.name                                              as servicio,
       l.name                                              as sede,
       se.starts_at at time zone coalesce(l.timezone, o.timezone) as hora_local,
       b.status,
       (select count(*) from booking_reschedules r where r.booking_id = b.id) as reprogramaciones
from bookings b
    inner join clients       c  on c.id  = b.client_id
    inner join sessions      se on se.id = b.session_id
    inner join services      s  on s.id  = se.service_id
    inner join locations     l  on l.id  = se.location_id
    inner join organizations o  on o.id  = s.organization_id
where b.code = (select code from bookings where id = 'dddd0000-0000-0000-0000-000000000001');
```

**26.** ¿Qué reservas se reprogramaron, de qué hora a cuál, si fue a última hora y cuántas reprogramaciones les quedan? HU-014. "A última hora" no se guarda: es haberla movido dentro de la ventana de cancelación gratis de la política que congeló la reserva.

```sql
select b.code,
       c.full_name     as cliente,
       de.starts_at    as estaba,
       a.starts_at     as quedo,
       r.reason        as motivo,
       r.rescheduled_at > de.starts_at - make_interval(mins => p.free_cancellation_window_minutes) as tardia,
       p.max_reschedules - count(*) over (partition by b.id) as le_quedan
from booking_reschedules r
    inner join bookings              b  on b.id  = r.booking_id
    inner join clients               c  on c.id  = b.client_id
    inner join sessions              de on de.id = r.from_session_id
    inner join sessions              a  on a.id  = r.to_session_id
    inner join organization_policies p  on p.id  = b.policy_id
order by r.rescheduled_at;
```

**27.** ¿Cuántas cancelaciones tuvo cada proveedor en los últimos 30 días y cuántas fueron tardías? HU-013. Tardía es cancelar dentro de la ventana gratis de la política de la reserva, y se calcula con la hora de la cancelación y la de la cita.

```sql
select o.name as proveedor,
       count(*) as canceladas,
       count(*) filter (where b.cancelled_at > se.starts_at - make_interval(mins => p.free_cancellation_window_minutes)) as tardias
from bookings b
    inner join sessions              se on se.id = b.session_id
    inner join services              s  on s.id  = se.service_id
    inner join organizations         o  on o.id  = s.organization_id
    inner join organization_policies p  on p.id  = b.policy_id
where b.status = 'CANCELLED'
  and b.cancelled_at >= now() - interval '30 days'
group by o.name
order by canceladas desc;
```

**28.** ¿Qué tanto falla la gente a cada servicio? HU-016. De las citas ya cerradas, qué porcentaje fue inasistencia.

```sql
select s.name as servicio,
       count(*) filter (where b.status = 'COMPLETED') as atendidas,
       count(*) filter (where b.status = 'NO_SHOW')   as inasistencias,
       round(100.0 * count(*) filter (where b.status = 'NO_SHOW') / count(*), 1) as pct_inasistencia
from bookings b
    inner join sessions se on se.id = b.session_id
    inner join services s  on s.id  = se.service_id
where b.status in ('COMPLETED', 'NO_SHOW')
group by s.name
order by pct_inasistencia desc, servicio;
```

**29.** ¿Qué reservas cerró el sistema solo, y cómo quedaron? HU-016. Son los cambios de estado sin persona detrás (changed_by nulo) que dejó sp_cerrar_reservas_vencidas.

```sql
select b.code,
       c.full_name    as cliente,
       se.starts_at   as cita,
       h.from_status  as estaba,
       h.to_status    as quedo,
       h.changed_at   as cerrada
from booking_status_changes h
    inner join bookings b  on b.id  = h.booking_id
    inner join clients  c  on c.id  = b.client_id
    inner join sessions se on se.id = b.session_id
where h.changed_by is null
  and h.to_status in ('COMPLETED', 'NO_SHOW')
order by h.changed_at desc;
```

**30.** ¿Qué recordatorios salen en los próximos dos días, a quién y por qué canal? HU-015. Es lo que lee el proceso que envía los avisos.

```sql
select n.due_at                as sale,
       c.full_name             as cliente,
       c.notification_channel  as canal,
       s.name                  as servicio,
       se.starts_at            as cita
from booking_notices n
    inner join bookings b  on b.id  = n.booking_id
    inner join clients  c  on c.id  = b.client_id
    inner join sessions se on se.id = b.session_id
    inner join services s  on s.id  = se.service_id
where n.kind = 'REMINDER'
  and n.processed_at is null
  and n.due_at < now() + interval '48 hours'
order by n.due_at;
```

**31.** ¿Qué reservas esperan a que alguien las confirme, y qué falta? HU-012. Una queda RESERVED porque el proveedor confirma a mano, porque el cliente todavía no verifica su correo (HU-001) o porque el cliente aún no la confirma.

```sql
select b.code,
       o.name        as proveedor,
       c.full_name   as cliente,
       se.starts_at  as cita,
       case when p.manual_confirmation then 'La confirma el proveedor'
            when c.status <> 'ACTIVE'  then 'El cliente no ha verificado su correo'
            else 'Falta que el cliente la confirme' end as falta
from bookings b
    inner join clients               c  on c.id  = b.client_id
    inner join sessions              se on se.id = b.session_id
    inner join services              s  on s.id  = se.service_id
    inner join organizations         o  on o.id  = s.organization_id
    inner join organization_policies p  on p.id  = b.policy_id
where b.status = 'RESERVED'
  and se.starts_at > now()
order by se.starts_at;
```

**32.** ¿Qué días y a qué horas se concentra la demanda de cada proveedor? HU-020. Cuenta las reservas no canceladas de los últimos 60 días y las que vienen, por día de la semana y hora de la sede. El nombre del día sale de una lista y no de to_char, que lo daría en el idioma del servidor.

```sql
select o.name as proveedor,
       (array['1 lunes', '2 martes', '3 miércoles', '4 jueves', '5 viernes', '6 sábado', '7 domingo'])
           [extract(isodow from se.starts_at at time zone coalesce(l.timezone, o.timezone))]  as dia,
       extract(hour from se.starts_at at time zone coalesce(l.timezone, o.timezone))    as hora,
       count(*)                                                                         as reservas
from bookings b
    inner join sessions      se on se.id = b.session_id
    inner join services      s  on s.id  = se.service_id
    inner join organizations o  on o.id  = s.organization_id
    inner join locations     l  on l.id  = se.location_id
where b.status <> 'CANCELLED'
  and se.starts_at >= now() - interval '60 days'
group by o.name, dia, hora
order by o.name, dia, hora;
```

**33.** ¿Cuántas franjas le quedan libres mañana a cada servicio en cada sede? HU-008 y HU-011. Llama a fn_franjas_disponibles por cada servicio y sede con lateral.

```sql
select s.name      as servicio,
       l.name      as sede,
       count(f.*)  as franjas_libres,
       min(f.starts_at) as primera
from service_locations sl
    inner join services  s on s.id = sl.service_id
    inner join locations l on l.id = sl.location_id
    left join lateral fn_franjas_disponibles(sl.service_id, sl.location_id, current_date + 1) f on true
where s.status = 'ACTIVE'
group by s.name, l.name
order by s.name, l.name;
```

</details>

## 7. Estimación de volumen

**Supuestos.** La plataforma arranca en el Valle de Aburrá con 200 proveedores y suma 40 por mes, así
que termina el primer año con 680. En el año hay en promedio (200 + 680) / 2 = **440 proveedores
activos**. Cada proveedor tiene en promedio 1,5 sedes, 8 servicios y 6 recursos por sede, y atiende
10 reservas por día (300 al mes). De los 8 servicios, 1 es grupal: 1 de cada 8 reservas cae en un taller,
y un taller junta en promedio 4 reservas por sesión. Los clientes arrancan en 20 000 y suman 3 000 por
mes.

| Tabla | Al lanzar | Crece por mes (mes 12) | Fin del año 1 | De dónde sale |
|---|---|---|---|---|
| `organizations` | 200 | 40 | 680 | supuesto de adopción |
| `locations` | 300 | 60 | 1 020 | 1,5 por proveedor |
| `services` | 1 600 | 320 | 5 440 | 8 por proveedor |
| `resources` | 1 800 | 360 | 6 120 | 6 por sede |
| `agendas` | 1 800 | 360 | 6 120 | una agenda por recurso |
| `schedules` | 10 800 | 2 160 | 36 720 | 6 bloques por semana en cada agenda |
| `agenda_exceptions` | — | 9 180 | 71 280 | 18 festivos al año: 1,5 por agenda al mes; en el año, 18 × 3 960 agendas en promedio |
| `clients` | 20 000 | 3 000 | 56 000 | supuesto de adopción |
| **`bookings`** | — | 204 000 | **1 584 000** | 440 proveedores × 300 reservas × 12 meses |
| `sessions` | — | 184 875 | 1 435 500 | una por reserva individual (7/8) y una por cada 4 reservas grupales (1/8): 0,90625 por reserva |
| `session_resources` | — | 221 850 | 1 722 600 | 1,2 recursos por sesión |
| `booking_status_changes` | — | 612 000 | 4 752 000 | 3 filas por reserva: el estado con que nace, la confirmación y el cierre. Desde el Sprint 3 todo cambio de estado deja su fila |
| `booking_reschedules` | — | 20 400 | 158 400 | **S3.** Se reprograma 1 de cada 10 reservas |
| `booking_notices` | — | 877 200 | 6 811 200 | **S3.** 4,3 avisos por reserva: creación, confirmación, dos recordatorios y, en 3 de cada 10, una cancelación o una reprogramación |
| `organization_booking_reminders` | 400 | 80 | 1 360 | **S3.** 2 recordatorios por proveedor |
| `payments` | — | 214 200 | 1 663 200 | 1 por reserva y un 5 % de reintentos |
| `booking_reviews` | — | 30 600 | 237 600 | califica 1 de cada 4 reservas completadas (60 %) |
| `waitlist_entries` | — | 6 120 | 47 520 | 3 % de las reservas |
| `resource_occupancy_daily` | — | 183 600 | 1 445 400 | una fila por recurso por día: 3 960 recursos en promedio × 365 |
| `login_attempts` | — | 224 000 | 1 824 000 | 4 ingresos por cliente al mes, 38 000 clientes en promedio |
| `sent_emails` | — | 408 000 | 3 168 000 | 2 correos por reserva: confirmación y recordatorio |
| `audit_log` | — | 466 000 | 3 693 000 | ver el desglose abajo |
| `audit_log_changes` | — | 2 796 000 | 22 158 000 | 6 columnas por evento: un alta guarda unas 10 y un cambio 2 o 3 |

`audit_log` suma los eventos de las tablas auditadas. En el año: pagos 2 × 1 663 200 = 3 326 400
(alta y cambio de estado), clientes 2 × 56 000 = 112 000 (alta y verificación), servicios
2 × 5 440 = 10 880 (alta y activación), miembros 3 × 680 = 2 040, proveedores 2 × 680 = 1 360
(alta y aprobación), políticas 2 × 680 = 1 360 (versión inicial y un cambio) y reseñas 237 600 (una
alta cada una). En el Sprint 3 se suman los recordatorios: un alta por cada una de sus 1 360 filas. En
total 3 693 000. En el mes 12: 2 × 214 200 + 2 × 3 000 + 2 × 320 + 3 × 40 + 2 × 40 + 2 × 40 + 30 600 +
80 = 466 000.

`booking_notices` es la segunda que más crece. Un aviso enviado no sirve de nada después de unos
meses, así que es la candidata a que un job del administrador borre los procesados de más de 90 días;
`rol_app` no tiene permiso de borrar en ella.

`audit_log_changes` es la tabla que más crece. Es lo que cuesta guardar cada valor por separado en vez
de la fila entera en un `jsonb`, y por eso es la candidata natural a particionarse por mes y archivarse.

Las historias de estado de cuentas (`organization_status_changes`, `client_status_changes`) y los
catálogos (`cities`, `organization_categories`, `currencies`) quedan por debajo de unos pocos miles de
filas al año.

`bookings` termina el año con 1,58 millones de filas y unos 213 MB según la fórmula del curso, con la
fila del Sprint 2; con el código del Sprint 3 serían unos 243 MB (ver la sección 9). Medido
en PostgreSQL son 238 MB, y `sessions` otros 150 MB. Lo crucé generando ese volumen con
[`docs/generar-volumen.sql`](docs/generar-volumen.sql); el detalle está en el
[análisis de almacenamiento](docs/analisis-almacenamiento.md).

## 8. Roles y seguridad

### Los roles

Separo tres funciones del sistema. Cada una es un rol de grupo sin login: las personas y los servicios
entran con un usuario propio que hereda de uno de ellos. Así ninguna contraseña queda en el
repositorio.

| Rol | Quién lo usa | Qué necesita |
|---|---|---|
| `rol_admin` | administración de la base y soporte | todo |
| `rol_app` | el backend Spring Boot | sólo lo que el código hace |
| `rol_lectura` | reportes, analítica, BI | leer, pero no nombres, documentos, datos de contacto ni de seguridad |

Además, en Supabase existen `anon` y `authenticated`, los roles del Data API. Ahí todo está cerrado
salvo lo que abren las políticas RLS.

### Matriz de permisos

S = select, I = insert, U = update, D = delete.

| Tablas | rol_admin | rol_app | rol_lectura | authenticated | anon |
|---|---|---|---|---|---|
| Catálogos: `cities`, `organization_categories`, `currencies` | todo | S | S | S | S |
| `clients` | todo | S I U | — | — | — |
| `organizations` | todo | S I U | S, sin documento ni contacto | — | — |
| Operación: `organization_members`, `organization_policies`, `locations`, `resource_types`, `service_resource_requirements`, `resources`, `resource_maintenances`, `agendas` | todo | S I U | S | — | — |
| Tablas que son sólo una clave: `service_locations`, `agenda_services` | todo | S I | S | — | — |
| `services`, `schedules`, `agenda_exceptions` | todo | S I U **D** | S | — | — |
| `sessions`, `waitlist_entries` | todo | S I U | S | S, sólo las propias | — |
| `bookings` | todo | S; I sólo de lo que pide el cliente (no `code` ni las fechas); U sólo de la sesión y el estado | S | S, sólo las propias | — |
| `booking_reviews` | todo | S I U | S, sin el comentario | S, sólo las propias | — |
| `session_resources` | todo | S I U | S | — | — |
| `payments` | todo | S I, U sólo de estado, referencia y fechas | S | — | — |
| Historiales: `booking_status_changes`, `organization_status_changes` | todo | S I | S | — | — |
| **S3** `booking_reschedules` (historial) | todo | S I | S | S, sólo las propias | — |
| **S3** `organization_booking_reminders` | todo | S I **D** | S | — | — |
| **S3** `booking_notices` | todo | S, U sólo de `processed_at` | S | S, sólo las propias | — |
| `client_status_changes`, `login_attempts`, `sent_emails` | todo | S I | — | — | — |
| `resource_occupancy_daily` | todo | S | S | — | — |
| `audit_log`, `audit_log_changes` | todo | — | — | — | — |

Por qué está así:

- **rol_app no borra**, salvo en tres tablas. Revisé el código del backend: `ManageServiceUseCase`
  borra un servicio que nunca se reservó y `AgendaRepositoryAdapter` reescribe los bloques de una
  agenda con `delete` + `insert`. Una excepción de agenda mal puesta también tiene que poder quitarse.
  Fuera de eso, nada se borra: una reserva se cancela, un recurso se retira y un servicio se
  desactiva.
- **Lo pactado no se edita.** De `bookings` rol_app sólo puede cambiar la sesión, los asistentes, el
  estado y la fecha de cancelación; el cliente, el precio, la moneda y la política quedan como se
  crearon. De `payments`, sólo el estado, la referencia de la pasarela y las fechas. Y las tablas que
  son sólo una clave (`service_locations`, `agenda_services`) se crean, no se editan. Son permisos por
  columna.
- **Los historiales sólo crecen.** rol_app les agrega filas pero no las edita. Si los pudiera editar,
  dejarían de servir como evidencia de lo que pasó.
- **Los catálogos se cargan por migración** (V5 del equipo). La aplicación sólo los lee.
- **La auditoría no la toca nadie más que el administrador.** La escribe el trigger `fn_auditar`, que
  es `security definer`. Así rol_app deja rastro de sus cambios sin poder leer ni borrar ese rastro.
- **rol_app no borra recursos de una sesión.** Cuando se cancela la última reserva viva de una sesión,
  sus recursos se sueltan solos con `fn_sessions_libera_recursos`, que también es `security definer`.
- **rol_lectura no ve a quién pertenecen los datos.** No lee `clients`, su historia de estados,
  `sent_emails` ni `login_attempts`. De `organizations` no ve el documento, el correo ni el teléfono, porque desde V4
  un proveedor puede ser una persona natural con cédula. De `booking_reviews` no ve el comentario, que
  es texto libre del cliente. Eso se hace con permisos por columna. Sí ve los `uuid` de cliente y de
  usuario, porque un reporte necesita contar clientes distintos, pero sin `clients` no los puede
  convertir en nombres ni en correos. La dirección de una sede sí la ve: es la de un local abierto al
  público.
- **Las fechas de una reserva las pone la base.** Desde el Sprint 3 rol_app inserta en `bookings` sólo
  las columnas que pide el cliente. `created_at` es de donde `tg_bookings_anticipacion` mide la
  anticipación: si la aplicación pudiera fecharla ayer, se saltaría HU-012. Y `cancelled_at` la fija
  `tg_bookings_momento_del_estado` al cancelar y ya no se edita, porque de ella sale si la cancelación
  fue tardía. Tampoco se editan los asistentes: el precio se pactó por persona, y cambiarlos es cancelar
  y reservar otra vez. En el Sprint 2 rol_app podía editar las dos columnas.
- **La cola de avisos la llena la base.** `booking_notices` la escribe `tg_bookings_avisos`, que es
  `security definer`. El backend sólo la lee y marca lo que envió, así que no puede inventarse un aviso
  ni borrar uno pendiente.
- **Un recordatorio se quita borrando su fila.** Es configuración del proveedor, como sus bloques de
  agenda, y queda auditada.
- **Nadie crea objetos en `public`** salvo rol_admin.

### EXECUTE sobre procedimientos y funciones

**Cambio frente al Sprint 2.** PostgreSQL le da `EXECUTE` a `PUBLIC`, es decir, a cualquier usuario,
sobre toda función o procedimiento que se crea. En el Sprint 2 se lo quitaba sólo a las dos funciones
que se invocaban a mano. Ahora un bloque al final de `schema.sql` se lo quita a todas las rutinas propias,
y `alter default privileges` hace lo mismo con las que se creen después. Se dejan sólo las de
`btree_gist` y el constructor del tipo `timerange`, que no son nuestras y las usan los `EXCLUDE`.

| Rutina | HU | rol_admin | rol_app | rol_lectura | PUBLIC |
|---|---|---|---|---|---|
| `sp_crear_reserva`, `sp_cancelar_reserva`, `sp_reprogramar_reserva`, `sp_registrar_asistencia`, `sp_cerrar_reservas_vencidas` | 012 a 016 | sí | sí | — | — |
| `fn_historial_cliente`, `fn_comprobante_reserva` | 017, 018 | sí | sí | — (nombre y documento del cliente) | — |
| `fn_franjas_disponibles` | 008, 011 | sí | sí | sí | — |
| `fn_reporte_ocupacion` | 019 | sí | sí | sí | — |
| `fn_calcular_ocupacion` | 019 | sí | — (la corre el job diario) | — | — |
| Auxiliares: `f_sesion_para_reserva`, `f_recurso_atiende`, `f_sede_de_agenda`, `f_codigo_reserva`, `f_sin_tildes` | — | sí | sí | las que usan sus funciones | — |
| Funciones de trigger (`fn_bookings_*`, `fn_auditar`…) | — | sí | — | — | — |

Por qué está así:

- **Todo es `security invoker`.** Un procedimiento corre con los permisos de quien lo llama, así que
  no le abre a rol_app nada que sus `GRANT` no le den. Por eso rol_app necesita `EXECUTE` también sobre
  las auxiliares: PostgreSQL lo revisa en cada llamada anidada, incluso dentro de un trigger o de un
  `DEFAULT`, como el de `bookings.code`.
- **Las funciones de trigger no necesitan `EXECUTE`.** PostgreSQL no lo revisa al dispararlas, así que
  nadie distinto del administrador puede llamarlas a mano.
- **rol_lectura** ejecuta las dos funciones que no muestran a nadie: las franjas libres y la ocupación.
  El historial y el comprobante traen el nombre y el documento del cliente, igual que `clients`, que
  tampoco puede leer.
- **Sólo tres funciones son `security definer`**: las dos del Sprint 2, `fn_auditar` y
  `fn_sessions_libera_recursos`, y una nueva, `fn_bookings_avisos`. Las tres escriben donde el rol que dispara el
  trigger no puede escribir, y las tres fijan `search_path = public` para que nadie les cambie las tablas
  con un esquema propio.

### RLS

Activo RLS en las 35 tablas, siguiendo el ADR-0002 del equipo. Con RLS activo y sin políticas nadie
distinto del dueño ve filas, así que cada rol propio recibe su política. Las políticas abren filas y lo
que cada rol puede *hacer* lo siguen limitando los `GRANT`. El control de qué proveedor ve qué datos
lo hace el backend con `OrganizationAccess` (ADR-0008); la base no lo repite.

En Supabase las políticas son estas:

```sql
-- Cualquiera puede leer los catálogos
create policy cities_publico on cities for select to anon, authenticated using (true);

-- Cada cliente autenticado ve sólo sus reservas, las sesiones de esas reservas,
-- su lista de espera y sus reseñas
create policy reservas_propias on bookings for select to authenticated
    using (client_id = (select auth.uid()));
create policy sesiones_propias on sessions for select to authenticated
    using (exists (select 1 from bookings b where b.session_id = sessions.id and b.client_id = (select auth.uid())));
create policy espera_propia on waitlist_entries for select to authenticated
    using (client_id = (select auth.uid()));
create policy resenas_propias on booking_reviews for select to authenticated
    using (exists (select 1 from bookings b where b.id = booking_id and b.client_id = (select auth.uid())));

-- [S3] Las tablas nuevas: el cliente ve las reprogramaciones y los avisos de sus reservas
create policy reprogramaciones_propias on booking_reschedules for select to authenticated
    using (exists (select 1 from bookings b where b.id = booking_id and b.client_id = (select auth.uid())));
create policy avisos_propios on booking_notices for select to authenticated
    using (exists (select 1 from bookings b where b.id = booking_id and b.client_id = (select auth.uid())));
```

Las tres tablas del Sprint 3 tienen RLS activo como todas, con las políticas de los roles propios. Desde el
Data API un cliente ve sólo las reprogramaciones y los avisos de sus reservas, y los recordatorios de un
proveedor no los ve nadie. Lo probé con un `auth.uid()` simulado: Mariana ve sus tres reservas y nada más,
y `authenticated` no puede leer `clients` ni ejecutar procedimientos.

El bloque que las crea sólo corre si existen los roles de Supabase, así que el mismo `schema.sql`
funciona en un PostgreSQL local.

### Qué rol usa la aplicación

**Hoy el backend se conecta como `postgres`**, el dueño de las tablas. Lo dice el propio V2 del equipo:
así la aplicación ignora RLS. Eso le da al backend mucho más de lo que necesita: una inyección SQL
tendría permiso de borrar cualquier tabla.

Lo que propongo, y que este esquema ya deja listo:

```sql
create role app_bookingplatform login password '...' in role rol_app;   -- el backend
create role reportes login password '...' in role rol_lectura;           -- BI
```

Flyway seguiría migrando con el usuario dueño (`spring.flyway.user`) y la aplicación usaría
`app_bookingplatform`. Es un cambio de configuración del equipo, no de código, y queda como propuesta.

### Comprobado

Las pruebas 18 a 27 de [`pruebas-sprint3.sql`](pruebas-sprint3.sql) intentan lo que cada rol *no*
debe poder hacer con los objetos nuevos: rol_app escribe un aviso, cambia un código, borra una
reprogramación, recalcula la ocupación, fecha una reserva en el pasado, le cambia la fecha a una
cancelación o sube los asistentes sin tocar el precio; rol_lectura crea una reserva o lee un historial; y
un rol cualquiera consulta las franjas. Las diez terminan en `permission denied`. La parte 2 hace con rol_app
el ciclo completo de una reserva, procedimiento por procedimiento, sin un solo error.

Las pruebas 44 a 51 de [`pruebas-integridad.sql`](pruebas-integridad.sql) intentan lo que cada rol
*no* debe poder hacer con las tablas del Sprint 2, y todas terminan en `permission denied`. La parte 3 hace con rol_app lo que hace
el backend (crear una sesión, reservar, asignar un recurso, confirmar, pagar, cancelar otra reserva,
editar un servicio y reescribir los bloques de una agenda) y todo pasa, triggers incluidos. Al
cancelar, la sesión suelta su silla aunque rol_app no tenga permiso de borrar. También corre con rol_lectura un reporte de calificaciones.
Las políticas de Supabase las probé con un `auth.uid()` simulado: un cliente ve sólo sus reservas y no
puede leer `clients` ni crear pagos.

## 9. Análisis de almacenamiento, costo y optimización

Es la entrega del Sprint 2 y está en [`docs/analisis-almacenamiento.md`](docs/analisis-almacenamiento.md).
La rúbrica del Sprint 3 no lo pide otra vez, así que no lo rehice. Sólo una nota: `bookings` ganó `code`,
unos 19 bytes por fila (18 caracteres y 1 de cabecera). Con eso L sube de 135 a unos 154 bytes, FR baja
de 58 a 51 y BR sube de 27 311 a 31 059 páginas, unos 243 MB. Lo demás del análisis no cambia. El
resumen de abajo es el del Sprint 2:

- **Tabla analizada:** `bookings`, con la fila del Sprint 2. L = 135 bytes, FR = 58, BR = 27 311 páginas (213 MB). El índice
  `pk_bookings` tiene orden d = 186, altura 3 y como máximo 8 564 nodos (67 MB). PostgreSQL mide
  30 462 páginas y un índice de altura 3 con 8 075 páginas.
- **Costo:** la consulta 24 une servicios, sesiones y reservas. Con ciclos anidados e índices cuesta
  932 páginas, frente a 2 868 si `sessions` sólo tuviera índice sobre `service_id`, 42 275 del hash join
  y 211 727 del ordenamiento y mezcla. El plan real lee 989.
- **Optimización:** de E₀, con un producto de 1,24 × 10¹⁶ tuplas, a E₁, que filtra y proyecta antes de
  las reuniones con las leyes 2, 12, 4/5, 9, 3, 8 y 11. El orden elegido deja 176 tuplas en medio en
  vez de 99 000, y llegan 146 al agrupamiento.

## Dónde está cada criterio de la rúbrica

La rúbrica del Sprint 3 califica lo nuevo o modificado frente al Sprint 2. Está resumido en
[Cambios respecto al Sprint 2](#cambios-respecto-al-sprint-2).

| # | Criterio | Dónde |
|---|---|---|
| 1 | MER refinado, consistente con el script y con cada cambio justificado | [Sección 1](#1-mer-refinado), [cambios](#cambios-respecto-al-sprint-2) y [normalización](#normalización) |
| 2 | Script refinado, ejecutable en una base vacía | [`schema.sql`](schema.sql), [sección 2](#2-modelo-físico) y [sección 3](#3-schemasql) |
| 3 | Triggers asociados a las HU, con evento, momento y propósito | [Sección 4](#4-triggers) y pruebas 1 a 17 de [`pruebas-sprint3.sql`](pruebas-sprint3.sql) |
| 4 | Procedimientos y funciones de las HU, con parámetros, resultado y ejemplo de llamada | [Sección 5](#5-procedimientos-y-funciones) y parte 2 de [`pruebas-sprint3.sql`](pruebas-sprint3.sql) |
| 5 | Consultas ajustadas y nuevas, cada una con su pregunta y su HU | [Sección 6](#6-consultas) y [`consultas.sql`](consultas.sql) |
| 6 | Roles y seguridad actualizados, con EXECUTE y mínimo privilegio | [Sección 8](#8-roles-y-seguridad), el final de `schema.sql` y pruebas 18 a 27 |
