-- ================================================================
-- TallerNeto · Aplicar pr_cambiar_nombre en PRODUCCIÓN
-- Proyecto Supabase «staffride» (ref qkwzcbdocriuwfblndlk).
-- Pegar y ejecutar UNA vez en el SQL Editor de ese proyecto (cuenta ml).
-- Función extraída tal cual de servidor/esquema.sql (2026-11-21),
-- donde quedó probada en local (pruebas 13-15 PASS).
-- Es aditiva: sin ella, la opción «Cambiar mi nombre» del panel
-- se ve pero falla al usarla; el redespliegue del panel de
-- producción espera a que esta función exista.
-- ================================================================

-- Cambiar MI nombre visible: autoservicio, mismo patrón que
-- pr_cambiar_pin — el PIN actual es la credencial que autoriza, así
-- que cada quien solo puede cambiar SU propio nombre. El nombre no
-- es una credencial: a diferencia del cambio de PIN, las sesiones
-- NO se revocan (nadie sale expulsado por corregir su nombre).
create or replace function pr_cambiar_nombre(p_usuario uuid, p_pin_actual text,
                                             p_nombre_nuevo text)
returns boolean language plpgsql security definer as $$
declare
  u usuarios;
  v_nombre text;
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  if not pr_verificar_pin(p_pin_actual, u.pin_hash) then
    raise exception 'El PIN actual no es correcto';
  end if;
  v_nombre := trim(coalesce(p_nombre_nuevo, ''));
  if length(v_nombre) = 0 then
    raise exception 'El nombre nuevo no puede estar vacío';
  end if;
  if length(v_nombre) > 120 then
    raise exception 'El nombre nuevo es demasiado largo (máximo 120 caracteres)';
  end if;
  update usuarios set nombre = v_nombre where id = p_usuario;
  perform pr_registrar_accion(u.empresa_id, p_usuario, 'nombre_cambiado',
    format('Cambió su nombre de «%s» a «%s»', u.nombre, v_nombre));
  return true;
end;
$$;
