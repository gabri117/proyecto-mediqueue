# Notas de seguridad

Esta configuracion es local/dev. No debe usarse igual en produccion.

Requisitos minimos para produccion:

- No versionar passwords reales.
- Usar TLS para PostgreSQL, Patroni REST y etcd.
- Proteger la API REST de Patroni.
- Restringir puertos expuestos.
- Separar usuarios de aplicacion, administracion y replicacion.
- Rotar credenciales.
- Definir RPO/RTO y validar restores periodicamente.
