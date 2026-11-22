-- ================================================================
-- TallerNeto · GESTIÓN DEL DUEÑO: LICENCIAS, PIN Y REGISTRO GLOBAL
-- (admin-gestion-dueno.sql)
--
-- Paridad con RutaNeto (pr_admin_licencia, pr_admin_pin_admin y
-- pr_admin_registro de pago-rutas): hasta hoy el dueño de TallerNeto
-- solo podía CREAR y LISTAR empresas (admin-crear-empresa.sql); la
-- licencia no se podía extender ni suspender desde ningún panel, el
-- PIN de un administrador no se podía reiniciar y la auditoría no
-- se podía consultar de forma global.
--
-- Archivo NUEVO, independiente, aditivo e idempotente (create or
-- replace): se aplica DESPUÉS de toda la pila vigente (esquema +
-- extensiones + admin-crear-empresa.sql). NO toca ninguna función
-- existente.
--
-- Qué trae (todo SOLO superadmin, con su sesión token validada
-- como en pr_admin_empresas / pr_admin_crear_empresa:
-- pr_validar_token + pr_exigir_superadmin):
--  - pr_admin_licencia: activar / suspender / extender (+N meses)
--    la licencia de una empresa. Al suspender, pr_iniciar_sesion
--    ya bloquea la entrada de esa empresa (valida el estado de la
--    licencia); al extender una licencia vencida, el conteo parte
--    de HOY (pr_hoy), no de la fecha vieja. Cada movimiento queda
--    en la auditoría (registro_actividad).
--  - pr_admin_pin_admin: LA excepción del dueño (como en
--    RutaNeto): reinicia el PIN del administrador de una empresa
--    sin conocer el actual. El PIN nuevo sigue la regla de la casa
--    (4 a 6 dígitos, nunca '1234'), se guarda solo su hash y las
--    sesiones de ese administrador se revocan (como hace
--    pr_cambiar_pin). Devuelve el código del administrador.
--  - pr_admin_registro: el registro GLOBAL de actividad (todas
--    las empresas, o una), con el mismo formato de salida que el
--    pr_admin_registro de RutaNeto para que el Súper Panel lo
--    pinte igual. registro_actividad no guarda foto del actor:
--    nombre/código/rol salen del usuario actual (left join).
--  - pr_admin_fijar_extra: activar o desactivar DIRECTAMENTE un
--    extra (Lavado / Combustible) en una empresa, sin esperar su
--    solicitud. Delega en el mecanismo de siempre
--    (pr_configurar_lavado / pr_configurar_combustible, que
--    encienden/apagan empresas.lavado_activo / combustible_activo
--    y dejan su fila en la auditoría): no duplica esa lógica. Si
--    al activar había una solicitud pendiente de ese módulo, la
--    deja resuelta como aprobada por el dueño (era exactamente
--    lo que la empresa estaba pidiendo).
--  - pr_admin_empresas se REDEFINE de forma aditiva (mismo
--    cuerpo de admin-crear-empresa.sql + la clave «extras» con el
--    estado de Lavado/Combustible de cada empresa) para que los
--    paneles del dueño puedan MOSTRAR ese estado; los clientes
--    actuales ignoran la clave nueva.
--
-- El dueño NO opera dentro de las empresas con esto: gestiona
-- licencias y accesos desde fuera, y todo queda registrado.
-- ================================================================

-- ============ GESTIONAR LA LICENCIA DE UNA EMPRESA ============
create or replace function pr_admin_licencia(p_quien uuid, p_token text,
                                             p_empresa uuid, p_accion text,
                                             p_meses int default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  lic licencias;
  emp empresas;
  v_accion text;
  v_detalle text;
begin
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);

  select * into emp from empresas where id = p_empresa;
  if emp.id is null then raise exception 'Esa empresa no existe'; end if;
  select * into lic from licencias
  where empresa_id = p_empresa order by creada_en desc limit 1;
  if lic.id is null then raise exception 'Esta empresa no tiene licencia'; end if;

  if p_accion = 'activar' then
    update licencias set estado = 'activa' where id = lic.id returning * into lic;
    v_accion := 'licencia_activada';
    v_detalle := format('Activó la licencia de la empresa «%s»', emp.nombre);
  elsif p_accion = 'suspender' then
    update licencias set estado = 'suspendida' where id = lic.id returning * into lic;
    v_accion := 'licencia_suspendida';
    v_detalle := format('Suspendió la licencia de la empresa «%s»', emp.nombre);
  elsif p_accion = 'extender' then
    if p_meses is null or p_meses <= 0 then
      raise exception 'Para extender la licencia indica los meses';
    end if;
    if p_meses > 120 then
      raise exception 'La licencia no puede extenderse más de 120 meses de una vez';
    end if;
    -- Si ya venció (o no tenía fecha), el tiempo nuevo corre desde
    -- HOY (hora de RD), no desde el vencimiento viejo.
    update licencias
    set estado = 'activa',
        vence = (greatest(coalesce(vence, pr_hoy()), pr_hoy())
                 + (p_meses || ' months')::interval)::date
    where id = lic.id returning * into lic;
    v_accion := 'licencia_extendida';
    v_detalle := format('Extendió la licencia de la empresa «%s» por %s meses (nuevo vencimiento: %s)',
                        emp.nombre, p_meses, to_char(lic.vence, 'DD/MM/YYYY'));
  else
    raise exception 'Acción no válida: %', p_accion;
  end if;

  perform pr_registrar_accion(p_empresa, q.id, v_accion, v_detalle);

  return jsonb_build_object('estado', lic.estado, 'vence', lic.vence,
                            'maxVehiculos', lic.max_vehiculos);
end;
$$;

-- ============ REINICIAR EL PIN DEL ADMINISTRADOR (excepción del dueño) ============
-- El detalle trae la empresa y el código del admin, nunca el PIN.
create or replace function pr_admin_pin_admin(p_quien uuid, p_token text,
                                              p_empresa uuid, p_pin_nuevo text)
returns text language plpgsql security definer as $$
declare
  q usuarios;
  adm usuarios;
  emp empresas;
  v_pin text := trim(coalesce(p_pin_nuevo, ''));
begin
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);

  -- Misma regla de PIN que pr_crear_usuario / pr_cambiar_pin.
  if v_pin !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN nuevo debe tener de 4 a 6 dígitos';
  end if;
  if v_pin = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;

  select * into emp from empresas where id = p_empresa;
  if emp.id is null then raise exception 'Esa empresa no existe'; end if;
  select * into adm from usuarios
  where empresa_id = p_empresa and rol = 'admin' and activo
  order by codigo limit 1;
  if adm.id is null then
    raise exception 'Esta empresa no tiene usuario administrador';
  end if;

  update usuarios set pin_hash = pr_hash_pin(v_pin) where id = adm.id;
  -- Como en pr_cambiar_pin: el PIN nuevo echa fuera todas las
  -- sesiones vivas de ese administrador.
  perform pr_revocar_sesiones(adm.id);
  perform pr_registrar_accion(p_empresa, q.id, 'pin_admin_reiniciado',
    format('Reinició el PIN del administrador %s de la empresa «%s»', adm.codigo, emp.nombre));
  return adm.codigo;
end;
$$;

-- ============ FIJAR UN EXTRA DIRECTAMENTE (sin solicitud) ============
create or replace function pr_admin_fijar_extra(p_quien uuid, p_token text,
                                                p_empresa uuid, p_modulo text,
                                                p_activo boolean)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  emp empresas;
  v_modulo text := lower(trim(coalesce(p_modulo, '')));
  s solicitudes_extras;
begin
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);

  select * into emp from empresas where id = p_empresa;
  if emp.id is null then raise exception 'Esa empresa no existe'; end if;
  if v_modulo not in ('lavado','combustible') then
    raise exception 'Módulo no válido: % (usa lavado o combustible)', p_modulo;
  end if;
  if p_activo is null then
    raise exception 'Indica si el extra queda activo o inactivo';
  end if;

  -- El encendido/apagado real es el de siempre (pr_configurar_*):
  -- actualiza empresas.*_activo y registra 'lavado_configurado' /
  -- 'combustible_configurado' en la auditoría. Aquí no se duplica.
  if v_modulo = 'lavado' then
    perform pr_configurar_lavado(p_empresa, p_activo, q.id);
  else
    perform pr_configurar_combustible(p_empresa, p_activo, q.id);
  end if;

  -- Si la empresa tenía una solicitud pendiente de ESTE módulo y
  -- el dueño lo acaba de activar directamente, la solicitud queda
  -- resuelta como aprobada (es lo que la empresa pedía); no queda
  -- una petición fantasma esperando en la bandeja.
  if p_activo then
    update solicitudes_extras
    set estado = 'aprobada', resuelta_por = q.id, resuelta_en = now(),
        nota = 'Activado directamente por el dueño, sin esperar la solicitud'
    where empresa_id = p_empresa and modulo = v_modulo and estado = 'pendiente'
    returning * into s;
    if s.id is not null then
      perform pr_registrar_accion(p_empresa, q.id, 'extra_aprobado',
        format('Se aprobó la solicitud y se ACTIVÓ el servicio extra de %s (activación directa del dueño)', v_modulo));
    end if;
  end if;

  select * into emp from empresas where id = p_empresa;
  return jsonb_build_object(
    'empresa', emp.nombre,
    'modulo', v_modulo,
    'activo', p_activo,
    'lavadoActivo', coalesce(emp.lavado_activo, false),
    'combustibleActivo', coalesce(emp.combustible_activo, false));
end;
$$;

-- ============ LISTADO DE EMPRESAS DEL DUEÑO (aditivo: + extras) ============
-- El mismo pr_admin_empresas de admin-crear-empresa.sql, con la
-- clave «extras» añadida a cada empresa. Nada más cambia.
create or replace function pr_admin_empresas(p_quien uuid, p_token text)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);
  return jsonb_build_object('empresas', coalesce((
    select jsonb_agg(fila order by nombre)
    from (
      select jsonb_build_object(
        'id', e.id,
        'nombre', e.nombre,
        'activa', e.activa,
        'creadaEn', e.creada_en,
        'licencia', case when lic.id is null then null else jsonb_build_object(
          'estado', lic.estado,
          'vence', lic.vence,
          'maxVehiculos', lic.max_vehiculos,
          'diasRestantes', case when lic.vence is null then null
                                else lic.vence - pr_hoy() end
        ) end,
        'extras', jsonb_build_object(
          'lavado', coalesce(e.lavado_activo, false),
          'combustible', coalesce(e.combustible_activo, false)
        ),
        'usuarios', (select count(*) from usuarios u where u.empresa_id = e.id),
        'vehiculos', (select count(*) from vehiculos v where v.empresa_id = e.id)
      ) as fila, e.nombre as nombre
      from empresas e
      left join lateral (
        select l.* from licencias l
        where l.empresa_id = e.id
        order by l.creada_en desc limit 1
      ) lic on true
    ) t
  ), '[]'::jsonb));
end;
$$;

-- ============ REGISTRO GLOBAL DEL DUEÑO ============
-- El registro de TODO el sistema (o de una empresa), solo
-- superadmin. Cada item trae además el nombre de la empresa.
create or replace function pr_admin_registro(p_quien uuid, p_token text,
                                             p_empresa uuid default null,
                                             p_limite int default 200)
returns jsonb language plpgsql security definer as $$
begin
  perform pr_validar_token(p_quien, p_token);
  perform pr_exigir_superadmin(p_quien);

  return coalesce((
    select jsonb_agg(item order by creada_en desc)
    from (
      select jsonb_build_object(
        'id', r.id,
        'empresaId', r.empresa_id,
        'empresa', e.nombre,
        'actor', jsonb_build_object(
          'nombre', coalesce(u.nombre, '—'),
          'codigo', coalesce(u.codigo, ''),
          'rol', coalesce(u.rol, '')),
        'accion', r.accion,
        'detalle', r.detalle,
        'creadaEn', r.creada_en
      ) as item,
      r.creada_en as creada_en
      from registro_actividad r
      left join empresas e on e.id = r.empresa_id
      left join usuarios u on u.id = r.actor_id
      where p_empresa is null or r.empresa_id = p_empresa
      order by r.creada_en desc
      limit greatest(coalesce(p_limite, 200), 0)
    ) t
  ), '[]'::jsonb);
end;
$$;
