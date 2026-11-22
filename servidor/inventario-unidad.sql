-- TallerNeto · Extensión: INVENTARIO POR UNIDAD (ficha de cada unidad)
-- Se aplica DESPUÉS de servidor/extras-contratacion.sql (es la última
-- extensión del orden oficial). NO modifica los archivos anteriores:
-- todo es idempotente (tablas nuevas + columna nueva + create or
-- replace) y NO altera lo ya aplicado en producción: pensado para
-- aplicarse igual en demo y en producción (proyecto «staffride»).
--
-- Idea de Miguel (2026-11-21): una FICHA por unidad con TODO lo que
-- la unidad lleva encima (sus llantas, sus repuestos, sus llaves,
-- sus herramientas…) para poder «pasarle inventario». Es DISTINTO
-- del inventario de almacén (piezas): esto es lo que va CON la
-- unidad, no lo que está en el estante.
--
-- FLUJO panel → app (aclaraciones de Miguel, 2026-11-21):
--  - El ADMINISTRADOR define en el PANEL qué debe llevar cada
--    unidad: crea y edita la lista de artículos esperados de cada
--    ficha (por unidad, partiendo de la plantilla base si quiere).
--    SOLO el admin edita la lista esperada.
--  - Esa MISMA lista aparece en la APP tal cual: quien pasa el
--    inventario (el mecánico, o cualquier usuario que el panel
--    autorice con la bandera `puede_inventario_unidad`) NO edita la
--    lista: solo verifica contra ella, marcando cada artículo
--    presente/bueno, dañado o faltante, con nota si hace falta.
--  - La app lee SIEMPRE la ficha vigente del servidor
--    (pr_datos_inventario_app): si el admin cambia la lista en el
--    panel, la app lo refleja al cargar la ficha. Nada de listas
--    fijas en la app.
--  - El resultado de cada pasada (faltantes/dañados) vuelve al
--    panel: historial de revisiones por unidad con las diferencias.
--
-- Mismos patrones pr_*: token de sesión vigente, actor/empresa,
-- pr_hoy() en hora RD, registro de actividad.

-- ============ BANDERA DE PERMISO POR USUARIO ============
-- Quién puede PASAR inventario: el mecánico (su rol ya lo habilita,
-- también como rol adicional), el admin, o cualquier usuario con
-- esta bandera encendida (la fija el admin desde el panel).
alter table usuarios add column if not exists puede_inventario_unidad boolean not null default false;

-- ============ PLANTILLA BASE DE LA EMPRESA ============
-- El molde con el que nacen las fichas nuevas. Cada empresa tiene
-- el suyo (editable solo por su admin); la primera vez se siembra
-- con la plantilla base del sistema (pr__inv_plantilla_base).
create table if not exists inv_unidad_plantilla (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nombre text not null,
  categoria text not null default 'otros'
    check (categoria in ('llantas','llaves','herramientas','seguridad','repuestos','otros')),
  cantidad int not null default 1 check (cantidad >= 1),
  orden int not null default 0,
  activa boolean not null default true,
  creada_en timestamptz not null default now()
);
create index if not exists idx_inv_plantilla_empresa
  on inv_unidad_plantilla(empresa_id, orden, nombre);
create unique index if not exists idx_inv_plantilla_nombre_unico
  on inv_unidad_plantilla(empresa_id, upper(nombre));

-- ============ LA FICHA: artículos asignados a CADA unidad ============
-- La lista esperada VIGENTE de una unidad (la edita solo el admin).
-- `estado` es el último estado conocido de cada artículo: nace
-- 'sin_revisar' y lo actualiza cada pasada de inventario.
create table if not exists inv_unidad_articulos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  vehiculo_id uuid not null references vehiculos(id) on delete cascade,
  nombre text not null,
  categoria text not null default 'otros'
    check (categoria in ('llantas','llaves','herramientas','seguridad','repuestos','otros')),
  cantidad_esperada int not null default 1 check (cantidad_esperada >= 1),
  estado text not null default 'sin_revisar'
    check (estado in ('sin_revisar','bueno','danado','faltante')),
  nota text,
  ultima_revision_en timestamptz,
  creada_en timestamptz not null default now(),
  actualizada_en timestamptz not null default now()
);
create index if not exists idx_inv_articulos_vehiculo
  on inv_unidad_articulos(empresa_id, vehiculo_id, nombre);
create unique index if not exists idx_inv_articulos_nombre_unico
  on inv_unidad_articulos(empresa_id, vehiculo_id, upper(nombre));

-- ============ REVISIONES («pasar inventario») ============
-- Cada pasada queda guardada: quién la hizo, cuándo, y el detalle
-- artículo por artículo. El detalle guarda el NOMBRE como copia:
-- si el admin edita o quita el artículo después, el historial de
-- esa pasada no cambia.
create table if not exists inv_unidad_revisiones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  vehiculo_id uuid not null references vehiculos(id) on delete cascade,
  usuario_id uuid not null references usuarios(id),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  nota text,
  total int not null default 0,
  buenos int not null default 0,
  danados int not null default 0,
  faltantes int not null default 0,
  creada_en timestamptz not null default now()
);
create index if not exists idx_inv_revisiones_vehiculo
  on inv_unidad_revisiones(empresa_id, vehiculo_id, creada_en desc);

create table if not exists inv_unidad_revision_detalle (
  id uuid primary key default gen_random_uuid(),
  revision_id uuid not null references inv_unidad_revisiones(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  articulo_id uuid references inv_unidad_articulos(id) on delete set null,
  nombre text not null,
  categoria text not null,
  cantidad_esperada int not null default 1,
  estado text not null check (estado in ('bueno','danado','faltante')),
  nota text
);
create index if not exists idx_inv_detalle_revision
  on inv_unidad_revision_detalle(revision_id);

-- RLS activa en todo: el acceso real pasa por las funciones pr_*.
alter table inv_unidad_plantilla enable row level security;
alter table inv_unidad_articulos enable row level security;
alter table inv_unidad_revisiones enable row level security;
alter table inv_unidad_revision_detalle enable row level security;

-- ================================================================
-- AYUDANTES
-- ================================================================

-- La plantilla base del sistema (lo mínimo que toda unidad de una
-- transportista debería llevar encima). La empresa la adapta a su
-- gusto: añade, quita y renombra desde el panel.
create or replace function pr__inv_plantilla_base()
returns table(nombre text, categoria text, cantidad int, orden int)
language sql immutable as $$
  select * from (values
    ('Llanta de repuesto',       'llantas',      1, 1),
    ('Juego de llaves de la unidad', 'llaves',   1, 2),
    ('Gato',                     'herramientas', 1, 3),
    ('Llave de ruedas',          'herramientas', 1, 4),
    ('Triángulo de seguridad',   'seguridad',    1, 5),
    ('Extintor',                 'seguridad',    1, 6),
    ('Botiquín',                 'seguridad',    1, 7),
    ('Chaleco reflectivo',       'seguridad',    1, 8),
    ('Herramientas básicas',     'herramientas', 1, 9)
  ) as t(nombre, categoria, cantidad, orden);
$$;

-- Siembra la plantilla de la empresa con la base, si aún no tiene
-- ninguna. Idempotente.
create or replace function pr__inv_asegurar_plantilla(p_empresa uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from inv_unidad_plantilla where empresa_id = p_empresa) then
    insert into inv_unidad_plantilla (empresa_id, nombre, categoria, cantidad, orden)
    select p_empresa, b.nombre, b.categoria, b.cantidad, b.orden
    from pr__inv_plantilla_base() b;
  end if;
end;
$$;

-- ¿Este usuario puede PASAR inventario? Mecánico (principal o
-- adicional), admin, o la bandera que el panel enciende.
create or replace function pr__inv_puede_pasar(p_usuario usuarios) returns boolean
language sql stable as $$
  select p_usuario.rol in ('mecanico','admin')
      or coalesce(p_usuario.rol_adicional, '') = 'mecanico'
      or coalesce(p_usuario.puede_inventario_unidad, false);
$$;

-- Estado general de la ficha de una unidad, derivado de sus
-- artículos y de si alguna vez se le pasó inventario:
--  sin_ficha     → el admin aún no le crea la lista esperada
--  sin_revisar   → tiene lista, pero nadie le ha pasado inventario
--  con_faltantes → algún artículo quedó marcado faltante
--  con_danados   → sin faltantes, pero algo quedó dañado
--  completa      → pasada y todo bueno
create or replace function pr__inv_estado_general(p_empresa uuid, p_vehiculo uuid)
returns text language plpgsql stable security definer as $$
declare
  v_total int;
  v_faltantes int;
  v_danados int;
  v_revisiones int;
begin
  select count(*),
         count(*) filter (where estado = 'faltante'),
         count(*) filter (where estado = 'danado')
    into v_total, v_faltantes, v_danados
  from inv_unidad_articulos
  where empresa_id = p_empresa and vehiculo_id = p_vehiculo;
  if v_total = 0 then return 'sin_ficha'; end if;
  select count(*) into v_revisiones
  from inv_unidad_revisiones
  where empresa_id = p_empresa and vehiculo_id = p_vehiculo;
  if v_revisiones = 0 then return 'sin_revisar'; end if;
  if v_faltantes > 0 then return 'con_faltantes'; end if;
  if v_danados > 0 then return 'con_danados'; end if;
  return 'completa';
end;
$$;

-- JSON de un artículo de ficha (la misma forma para panel y app).
create or replace function pr__inv_articulo_json(p_articulo inv_unidad_articulos)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_articulo.id,
    'nombre', p_articulo.nombre,
    'categoria', p_articulo.categoria,
    'cantidadEsperada', p_articulo.cantidad_esperada,
    'estado', p_articulo.estado,
    'nota', p_articulo.nota,
    'ultimaRevisionEn', p_articulo.ultima_revision_en
  );
$$;

-- JSON completo de una unidad con su ficha vigente: lo que el
-- panel pinta y lo que la app verifica. SIEMPRE sale de las
-- tablas actuales: es la ficha vigente del servidor.
create or replace function pr__inv_unidad_json(p_empresa uuid, p_vehiculo vehiculos)
returns jsonb language plpgsql stable security definer as $$
declare
  v_ult inv_unidad_revisiones;
begin
  select * into v_ult from inv_unidad_revisiones
  where empresa_id = p_empresa and vehiculo_id = p_vehiculo.id
  order by creada_en desc limit 1;
  return jsonb_build_object(
    'id', p_vehiculo.id, 'codigo', p_vehiculo.codigo, 'placa', p_vehiculo.placa,
    'marca', p_vehiculo.marca, 'modelo', p_vehiculo.modelo, 'anio', p_vehiculo.anio,
    'estado', p_vehiculo.estado, 'activo', p_vehiculo.activo,
    'tieneFicha', exists (
      select 1 from inv_unidad_articulos
      where empresa_id = p_empresa and vehiculo_id = p_vehiculo.id),
    'estadoGeneral', pr__inv_estado_general(p_empresa, p_vehiculo.id),
    'numArticulos', (select count(*) from inv_unidad_articulos
                     where empresa_id = p_empresa and vehiculo_id = p_vehiculo.id),
    'numFaltantes', (select count(*) from inv_unidad_articulos
                     where empresa_id = p_empresa and vehiculo_id = p_vehiculo.id
                       and estado = 'faltante'),
    'numDanados', (select count(*) from inv_unidad_articulos
                   where empresa_id = p_empresa and vehiculo_id = p_vehiculo.id
                     and estado = 'danado'),
    'ultimaRevisionEn', v_ult.creada_en,
    'ultimaRevisionPor', case when v_ult.id is null then null else
      (select nombre from usuarios where id = v_ult.usuario_id) end,
    'articulos', coalesce((
      select jsonb_agg(pr__inv_articulo_json(a) order by a.nombre)
      from inv_unidad_articulos a
      where a.empresa_id = p_empresa and a.vehiculo_id = p_vehiculo.id
    ), '[]'::jsonb)
  );
end;
$$;

-- Validación compartida de un artículo (ficha o plantilla).
create or replace function pr__inv_validar_articulo(p_nombre text, p_categoria text,
                                                    p_cantidad int)
returns void language plpgsql stable as $$
begin
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El artículo necesita un nombre';
  end if;
  if p_categoria not in ('llantas','llaves','herramientas','seguridad','repuestos','otros') then
    raise exception 'Categoría no válida: %', p_categoria;
  end if;
  if p_cantidad is null or p_cantidad < 1 then
    raise exception 'La cantidad esperada debe ser al menos 1';
  end if;
end;
$$;

-- ================================================================
-- DATOS DEL PANEL: plantilla, permisos y TODAS las unidades con
-- su ficha vigente y su estado general. La sección «Inventario
-- por unidad» pinta de aquí (RPC propia, como Servicios extra).
-- Lectura: admin y almacén (el panel de la empresa).
-- ================================================================
create or replace function pr_datos_inventario_unidad(p_empresa uuid,
                                                      p_quien uuid default null,
                                                      p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  select * into e from empresas where id = p_empresa;
  -- La plantilla nace con la base la primera vez que se abre la
  -- sección. En contextos de solo lectura (PostgREST) el insert
  -- puede no poder correr: se ignora y la plantilla sale vacía.
  begin
    perform pr__inv_asegurar_plantilla(p_empresa);
  exception when read_only_sql_transaction then
    null;
  end;
  return jsonb_build_object(
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'fecha', pr_hoy(),
    'plantilla', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'nombre', t.nombre, 'categoria', t.categoria,
        'cantidad', t.cantidad, 'orden', t.orden, 'activa', t.activa
      ) order by t.orden, t.nombre)
      from inv_unidad_plantilla t
      where t.empresa_id = p_empresa and t.activa
    ), '[]'::jsonb),
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol,
        'rolAdicional', u.rol_adicional,
        'puedeInventarioUnidad', coalesce(u.puede_inventario_unidad, false),
        'puedePasar', pr__inv_puede_pasar(u)
      ) order by u.codigo)
      from usuarios u where u.empresa_id = p_empresa and u.activo
    ), '[]'::jsonb),
    'unidades', coalesce((
      select jsonb_agg(pr__inv_unidad_json(p_empresa, v) order by v.codigo)
      from vehiculos v where v.empresa_id = p_empresa
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- DATOS DE LA APP: la ficha VIGENTE del servidor para las
-- unidades activas de MI empresa. La app la pide al entrar a la
-- pantalla y al recargar: si el admin cambió la lista en el
-- panel, aquí ya viene cambiada. Sin listas fijas en la app.
-- Puede VERLA cualquier usuario de la empresa; PASAR inventario
-- solo quien `puedePasar` (mecánico, admin o autorizado).
-- ================================================================
create or replace function pr_datos_inventario_app(p_quien uuid default null,
                                                   p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_empresa(u.empresa_id, p_quien, p_token);
  select * into e from empresas where id = q.empresa_id;
  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol,
      'rolAdicional', q.rol_adicional,
      'puedeInventarioUnidad', coalesce(q.puede_inventario_unidad, false)),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'fecha', pr_hoy(),
    'puedePasar', pr__inv_puede_pasar(q),
    'unidades', coalesce((
      select jsonb_agg(pr__inv_unidad_json(q.empresa_id, v) order by v.codigo)
      from vehiculos v where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- LA FICHA LA DEFINE SOLO EL ADMINISTRADOR (panel)
-- ================================================================

-- Crear la ficha de una unidad: nace con los artículos de la
-- plantilla de la empresa (o vacía, si así se pide). Si la unidad
-- ya tiene artículos, no se duplica: error claro.
create or replace function pr_crear_ficha_unidad(p_empresa uuid, p_vehiculo uuid,
                                                 p_desde_plantilla boolean default true,
                                                 p_quien uuid default null,
                                                 p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if exists (select 1 from inv_unidad_articulos
             where empresa_id = p_empresa and vehiculo_id = v.id) then
    raise exception 'La unidad % ya tiene su ficha creada', v.codigo;
  end if;
  if coalesce(p_desde_plantilla, true) then
    perform pr__inv_asegurar_plantilla(p_empresa);
    insert into inv_unidad_articulos (empresa_id, vehiculo_id, nombre, categoria, cantidad_esperada)
    select p_empresa, v.id, t.nombre, t.categoria, t.cantidad
    from inv_unidad_plantilla t
    where t.empresa_id = p_empresa and t.activa;
  end if;
  perform pr_registrar_accion(p_empresa, q.id, 'ficha_unidad_creada',
    format('Creó la ficha de inventario de la unidad %s (%s)%s',
           v.codigo, v.placa,
           case when coalesce(p_desde_plantilla, true)
                then ' desde la plantilla' else ' vacía' end));
  return pr__inv_unidad_json(p_empresa, v);
end;
$$;

-- Añadir un artículo a la ficha de una unidad (solo admin).
create or replace function pr_agregar_articulo_ficha(p_empresa uuid, p_vehiculo uuid,
                                                     p_nombre text, p_categoria text,
                                                     p_cantidad int default 1,
                                                     p_quien uuid default null,
                                                     p_token text default null)
returns inv_unidad_articulos language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  a inv_unidad_articulos;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  perform pr__inv_validar_articulo(p_nombre, p_categoria, p_cantidad);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if exists (select 1 from inv_unidad_articulos
             where empresa_id = p_empresa and vehiculo_id = v.id
               and upper(nombre) = upper(trim(p_nombre))) then
    raise exception 'La ficha de % ya tiene el artículo «%»', v.codigo, trim(p_nombre);
  end if;
  insert into inv_unidad_articulos (empresa_id, vehiculo_id, nombre, categoria, cantidad_esperada)
  values (p_empresa, v.id, trim(p_nombre), p_categoria, p_cantidad)
  returning * into a;
  perform pr_registrar_accion(p_empresa, q.id, 'ficha_unidad_editada',
    format('Añadió «%s» a la ficha de la unidad %s', a.nombre, v.codigo));
  return a;
end;
$$;

-- Editar un artículo de una ficha (solo admin): nombre, categoría
-- y cantidad esperada. El estado conocido NO se edita a mano: lo
-- pone la próxima pasada de inventario.
create or replace function pr_actualizar_articulo_ficha(p_articulo uuid,
                                                        p_nombre text, p_categoria text,
                                                        p_cantidad int,
                                                        p_quien uuid default null,
                                                        p_token text default null)
returns inv_unidad_articulos language plpgsql security definer as $$
declare
  a inv_unidad_articulos;
  q usuarios;
begin
  select * into a from inv_unidad_articulos where id = p_articulo;
  if a.id is null then raise exception 'Artículo no encontrado'; end if;
  q := pr_actor_con_rol(a.empresa_id, p_quien, p_token, array['admin']);
  perform pr__inv_validar_articulo(p_nombre, p_categoria, p_cantidad);
  if exists (select 1 from inv_unidad_articulos
             where empresa_id = a.empresa_id and vehiculo_id = a.vehiculo_id
               and id <> a.id and upper(nombre) = upper(trim(p_nombre))) then
    raise exception 'La ficha ya tiene otro artículo llamado «%»', trim(p_nombre);
  end if;
  update inv_unidad_articulos
  set nombre = trim(p_nombre), categoria = p_categoria,
      cantidad_esperada = p_cantidad, actualizada_en = now()
  where id = a.id
  returning * into a;
  perform pr_registrar_accion(a.empresa_id, q.id, 'ficha_unidad_editada',
    format('Editó el artículo «%s» de una ficha de unidad', a.nombre));
  return a;
end;
$$;

-- Quitar un artículo de una ficha (solo admin). El historial de
-- revisiones conserva el nombre del artículo (copia), así que
-- quitarlo no rompe las pasadas viejas.
create or replace function pr_quitar_articulo_ficha(p_articulo uuid,
                                                    p_quien uuid default null,
                                                    p_token text default null)
returns void language plpgsql security definer as $$
declare
  a inv_unidad_articulos;
  q usuarios;
begin
  select * into a from inv_unidad_articulos where id = p_articulo;
  if a.id is null then raise exception 'Artículo no encontrado'; end if;
  q := pr_actor_con_rol(a.empresa_id, p_quien, p_token, array['admin']);
  delete from inv_unidad_articulos where id = a.id;
  perform pr_registrar_accion(a.empresa_id, q.id, 'ficha_unidad_editada',
    format('Quitó «%s» de una ficha de unidad', a.nombre));
end;
$$;

-- ================================================================
-- LA PLANTILLA LA EDITA SOLO EL ADMINISTRADOR (panel)
-- (afecta a las fichas que se creen DESPUÉS, no a las existentes)
-- ================================================================
create or replace function pr_agregar_articulo_plantilla(p_empresa uuid,
                                                         p_nombre text, p_categoria text,
                                                         p_cantidad int default 1,
                                                         p_quien uuid default null,
                                                         p_token text default null)
returns inv_unidad_plantilla language plpgsql security definer as $$
declare
  q usuarios;
  t inv_unidad_plantilla;
  v_orden int;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  perform pr__inv_validar_articulo(p_nombre, p_categoria, p_cantidad);
  perform pr__inv_asegurar_plantilla(p_empresa);
  if exists (select 1 from inv_unidad_plantilla
             where empresa_id = p_empresa and upper(nombre) = upper(trim(p_nombre))) then
    raise exception 'La plantilla ya tiene el artículo «%»', trim(p_nombre);
  end if;
  select coalesce(max(orden), 0) + 1 into v_orden
  from inv_unidad_plantilla where empresa_id = p_empresa;
  insert into inv_unidad_plantilla (empresa_id, nombre, categoria, cantidad, orden)
  values (p_empresa, trim(p_nombre), p_categoria, p_cantidad, v_orden)
  returning * into t;
  perform pr_registrar_accion(p_empresa, q.id, 'plantilla_unidad_editada',
    format('Añadió «%s» a la plantilla de fichas de unidad', t.nombre));
  return t;
end;
$$;

create or replace function pr_actualizar_articulo_plantilla(p_plantilla uuid,
                                                            p_nombre text, p_categoria text,
                                                            p_cantidad int,
                                                            p_quien uuid default null,
                                                            p_token text default null)
returns inv_unidad_plantilla language plpgsql security definer as $$
declare
  t inv_unidad_plantilla;
  q usuarios;
begin
  select * into t from inv_unidad_plantilla where id = p_plantilla;
  if t.id is null then raise exception 'Artículo de plantilla no encontrado'; end if;
  q := pr_actor_con_rol(t.empresa_id, p_quien, p_token, array['admin']);
  perform pr__inv_validar_articulo(p_nombre, p_categoria, p_cantidad);
  if exists (select 1 from inv_unidad_plantilla
             where empresa_id = t.empresa_id and id <> t.id
               and upper(nombre) = upper(trim(p_nombre))) then
    raise exception 'La plantilla ya tiene otro artículo llamado «%»', trim(p_nombre);
  end if;
  update inv_unidad_plantilla
  set nombre = trim(p_nombre), categoria = p_categoria, cantidad = p_cantidad
  where id = t.id
  returning * into t;
  perform pr_registrar_accion(t.empresa_id, q.id, 'plantilla_unidad_editada',
    format('Editó el artículo «%s» de la plantilla de fichas', t.nombre));
  return t;
end;
$$;

create or replace function pr_quitar_articulo_plantilla(p_plantilla uuid,
                                                        p_quien uuid default null,
                                                        p_token text default null)
returns void language plpgsql security definer as $$
declare
  t inv_unidad_plantilla;
  q usuarios;
begin
  select * into t from inv_unidad_plantilla where id = p_plantilla;
  if t.id is null then raise exception 'Artículo de plantilla no encontrado'; end if;
  q := pr_actor_con_rol(t.empresa_id, p_quien, p_token, array['admin']);
  delete from inv_unidad_plantilla where id = t.id;
  perform pr_registrar_accion(t.empresa_id, q.id, 'plantilla_unidad_editada',
    format('Quitó «%s» de la plantilla de fichas de unidad', t.nombre));
end;
$$;

-- ================================================================
-- PERMISO PARA PASAR INVENTARIO (solo admin): enciende o apaga
-- la bandera de un usuario de SU empresa. El mecánico y el admin
-- pueden siempre; la bandera habilita a los demás (p. ej. el
-- coordinador de lavado o alguien de almacén).
-- ================================================================
create or replace function pr_fijar_permiso_inventario(p_usuario uuid,
                                                       p_permiso boolean,
                                                       p_quien uuid default null,
                                                       p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  if u.empresa_id is null then
    raise exception 'El dueño del sistema no lleva este permiso';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  update usuarios set puede_inventario_unidad = coalesce(p_permiso, false)
  where id = u.id
  returning * into u;
  perform pr_registrar_accion(u.empresa_id, q.id, 'usuario_editado',
    format('Permiso de inventario por unidad de %s (%s): %s',
           u.codigo, u.nombre,
           case when coalesce(p_permiso, false) then 'AUTORIZADO a pasar inventario'
                else 'sin autorización' end));
  return u;
end;
$$;

-- ================================================================
-- PASAR INVENTARIO: verificar la unidad contra su ficha vigente.
-- p_resultados: [{ "articuloId": uuid, "estado": "bueno" |
-- "danado" | "faltante", "nota": texto opcional }, …] — debe
-- cubrir TODOS los artículos de la ficha, ni más ni menos: una
-- pasada a medias no es una pasada.
-- Guarda la revisión con su detalle, actualiza el estado conocido
-- de cada artículo y devuelve el resumen con las DIFERENCIAS
-- (dañados y faltantes) para que panel y app las muestren.
-- ================================================================
create or replace function pr_pasar_inventario_unidad(p_empresa uuid, p_vehiculo uuid,
                                                      p_resultados jsonb,
                                                      p_nota text default null,
                                                      p_quien uuid default null,
                                                      p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  r inv_unidad_revisiones;
  item jsonb;
  a inv_unidad_articulos;
  v_total int := 0;
  v_buenos int := 0;
  v_danados int := 0;
  v_faltantes int := 0;
  v_vistos uuid[] := '{}';
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no opera dentro de las empresas: entra como consulta';
  end if;
  if not pr__inv_puede_pasar(q) then
    raise exception 'Tu usuario no está autorizado a pasar inventario por unidad: pídele la autorización a administración';
  end if;
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;
  if p_resultados is null or jsonb_typeof(p_resultados) <> 'array' then
    raise exception 'Faltan los resultados de la revisión';
  end if;

  select count(*) into v_total
  from inv_unidad_articulos
  where empresa_id = p_empresa and vehiculo_id = v.id;
  if v_total = 0 then
    raise exception 'La unidad % aún no tiene ficha: administración debe crearla en el panel', v.codigo;
  end if;
  if jsonb_array_length(p_resultados) <> v_total then
    raise exception 'La revisión debe cubrir todos los artículos de la ficha (% de %)',
      jsonb_array_length(p_resultados), v_total;
  end if;

  -- Primero se valida TODO; si algo no cuadra, no se guarda nada.
  for item in select * from jsonb_array_elements(p_resultados) loop
    if item->>'estado' not in ('bueno','danado','faltante') then
      raise exception 'Estado no válido en la revisión: %', item->>'estado';
    end if;
    select * into a from inv_unidad_articulos
    where id = (item->>'articuloId')::uuid
      and empresa_id = p_empresa and vehiculo_id = v.id;
    if a.id is null then
      raise exception 'Un artículo de la revisión ya no está en la ficha vigente: recarga la ficha y repite la pasada';
    end if;
    if a.id = any (v_vistos) then
      raise exception 'El artículo «%» viene dos veces en la revisión', a.nombre;
    end if;
    v_vistos := v_vistos || a.id;
  end loop;

  insert into inv_unidad_revisiones (empresa_id, vehiculo_id, usuario_id, fecha, nota)
  values (p_empresa, v.id, q.id, pr_hoy(), nullif(trim(coalesce(p_nota, '')), ''))
  returning * into r;

  for item in select * from jsonb_array_elements(p_resultados) loop
    select * into a from inv_unidad_articulos where id = (item->>'articuloId')::uuid;
    insert into inv_unidad_revision_detalle
      (revision_id, empresa_id, articulo_id, nombre, categoria, cantidad_esperada, estado, nota)
    values (r.id, p_empresa, a.id, a.nombre, a.categoria, a.cantidad_esperada,
            item->>'estado', nullif(trim(coalesce(item->>'nota', '')), ''));
    update inv_unidad_articulos
    set estado = item->>'estado',
        nota = nullif(trim(coalesce(item->>'nota', '')), ''),
        ultima_revision_en = now(), actualizada_en = now()
    where id = a.id;
    if item->>'estado' = 'bueno' then v_buenos := v_buenos + 1;
    elsif item->>'estado' = 'danado' then v_danados := v_danados + 1;
    else v_faltantes := v_faltantes + 1; end if;
  end loop;

  update inv_unidad_revisiones
  set total = v_total, buenos = v_buenos, danados = v_danados, faltantes = v_faltantes
  where id = r.id
  returning * into r;

  perform pr_registrar_accion(p_empresa, q.id, 'inventario_unidad_pasado',
    format('Pasó inventario a la unidad %s (%s): %s buenos, %s dañados, %s faltantes',
           v.codigo, v.placa, v_buenos, v_danados, v_faltantes));

  return jsonb_build_object(
    'id', r.id, 'vehiculoId', v.id, 'vehiculoCodigo', v.codigo,
    'fecha', r.fecha, 'creadaEn', r.creada_en,
    'responsableId', q.id, 'responsableNombre', q.nombre,
    'nota', r.nota,
    'total', r.total, 'buenos', r.buenos, 'danados', r.danados, 'faltantes', r.faltantes,
    'diferencias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nombre', d.nombre, 'categoria', d.categoria, 'estado', d.estado, 'nota', d.nota
      ) order by d.estado, d.nombre)
      from inv_unidad_revision_detalle d
      where d.revision_id = r.id and d.estado <> 'bueno'
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- HISTORIAL DE REVISIONES de una unidad (panel): cada pasada con
-- su detalle completo — las diferencias se ven sin abrir nada más.
-- Lectura: admin y almacén.
-- ================================================================
create or replace function pr_historial_inventario_unidad(p_empresa uuid, p_vehiculo uuid,
                                                          p_quien uuid default null,
                                                          p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  return jsonb_build_object(
    'vehiculo', jsonb_build_object(
      'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
      'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo),
    'revisiones', coalesce((
      select jsonb_agg(x.rev order by x.creada_en desc)
      from (
        select r.creada_en,
               jsonb_build_object(
                 'id', r.id, 'fecha', r.fecha, 'creadaEn', r.creada_en,
                 'responsableId', r.usuario_id,
                 'responsableNombre', (select nombre from usuarios where id = r.usuario_id),
                 'nota', r.nota,
                 'total', r.total, 'buenos', r.buenos,
                 'danados', r.danados, 'faltantes', r.faltantes,
                 'detalles', coalesce((
                   select jsonb_agg(jsonb_build_object(
                     'nombre', d.nombre, 'categoria', d.categoria,
                     'cantidadEsperada', d.cantidad_esperada,
                     'estado', d.estado, 'nota', d.nota
                   ) order by d.estado, d.nombre)
                   from inv_unidad_revision_detalle d
                   where d.revision_id = r.id
                 ), '[]'::jsonb)
               ) as rev
        from inv_unidad_revisiones r
        where r.empresa_id = p_empresa and r.vehiculo_id = v.id
        order by r.creada_en desc
        limit 50
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- LOGIN: devuelve también la bandera de inventario por unidad.
-- (Copia fiel de pr_iniciar_sesion de roles.sql, con
-- 'puedeInventarioUnidad' añadido a los dos objetos `usuario`:
-- la app decide así si muestra la pantalla de inventario a un
-- rol que no es mecánico ni admin.)
-- ================================================================
create or replace function pr_iniciar_sesion(p_codigo text, p_pin text, p_contexto text default null)
returns jsonb language plpgsql security definer as $$
declare
  candidatos int := 0;
  u usuarios;
  e empresas;
  lic licencias;
  v_token text;
  v_expira timestamptz;
begin
  select count(*) into candidatos
  from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  if candidatos = 0 then
    raise exception 'Código o PIN incorrecto';
  end if;
  if candidatos > 1 then
    raise exception 'Ese código existe en más de una empresa. Pide ayuda a TallerNeto para entrar.';
  end if;

  select * into u from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  -- Superadmin (dueño del sistema): sin empresa ni licencia.
  if u.empresa_id is null then
    if p_contexto = 'panel' and u.rol <> 'superadmin' then
      raise exception 'Esta cuenta no entra por el panel de empresa';
    end if;
    v_token := pr_gen_token();
    v_expira := now() + interval '12 hours';
    insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
    values (u.id, null, p_contexto, pr_hash_token(v_token), v_expira);
    return jsonb_build_object(
      'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol, 'rolAdicional', u.rol_adicional, 'puedeInventarioUnidad', coalesce(u.puede_inventario_unidad, false)),
      'empresa', null,
      'licencia', null,
      'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
    );
  end if;

  select * into e from empresas where id = u.empresa_id;
  if e.id is null or not e.activa then
    raise exception 'Tu empresa está inactiva. Contacta a TallerNeto.';
  end if;

  select * into lic from licencias where empresa_id = e.id order by creada_en desc limit 1;
  if lic.id is null then
    raise exception 'Tu empresa todavía no tiene licencia. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'suspendida' then
    raise exception 'La licencia de tu empresa está suspendida. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'vencida' or (lic.vence is not null and lic.vence < pr_hoy()) then
    raise exception 'La licencia de tu empresa está vencida. Contacta a TallerNeto para renovarla.';
  end if;

  perform pr_registrar_accion(u.empresa_id, u.id, 'inicio_sesion',
    case p_contexto when 'panel' then 'Inició sesión por el panel'
                    else 'Inició sesión' end);

  v_token := pr_gen_token();
  v_expira := now() + interval '12 hours';
  insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
  values (u.id, u.empresa_id, p_contexto, pr_hash_token(v_token), v_expira);

  return jsonb_build_object(
    'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol, 'rolAdicional', u.rol_adicional, 'puedeInventarioUnidad', coalesce(u.puede_inventario_unidad, false)),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'licencia', jsonb_build_object(
      'estado', lic.estado,
      'vence', lic.vence,
      'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ),
    'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
  );
end;
$$;
