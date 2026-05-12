# Skill: Seguridad del Repositorio y Configuración

Esta guía de contexto previene la filtración de credenciales, llaves de API y configuraciones confidenciales cuando los agentes AI o desarrolladores trabajen en el Monorepo MediQueue, de cara a su publicación en la nube.

## Principios Fundamentales

- **Secrets as Environment (Configuración fuera del código)**: Ningún archivo que se suba al repositorio Git debe contener credenciales reales en texto claro. Todo secreto debe extraerse de variables de entorno inyectadas en tiempo de ejecución.
- **Single Source of Truth (Única fuente de verdad)**: Todas las variables locales de desarrollo deben estar documentadas en el archivo `.env.example` central de la raíz y replicadas localmente en un archivo `.env` (el cual está protegido en el `.gitignore` global).

---

## Las 5 Reglas de Oro de Seguridad

### 1. Prohibido Hardcodear Credenciales
NUNCA escribas contraseñas reales, tokens de API o llaves privadas directamente en archivos `application.properties` o `application.yml`, independientemente del perfil de Spring Boot (`default`, `docker`, `prod`, etc.).
*   *Incorrecto:* `spring.rabbitmq.password=rabbit123`
*   *Correcto:* `spring.rabbitmq.password=${RABBITMQ_PASS:rabbit123}`

### 2. Sincronización de Nombres de Bases de Datos
Todas las bases de datos deben usar nombres en plural para coincidir exactamente con el aprovisionamiento de PostgreSQL en [init-dbs.sql](file:///c:/basesDatos/mediqueue/infra/docker/init-dbs.sql):
*   `mediqueue_appointments` (appointment-service)
*   `mediqueue_notifications` (notification-service)
*   `mediqueue_payments` (payment-service)
*   `mediqueue_patients` (patient-service)
*   `mediqueue_schedules` (schedule-service)

### 3. Mantener el `.gitignore` Global de la Raíz
Cualquier secreto local (como el archivo `.env` o llaves `.pem` de desarrollo) debe guardarse únicamente en la raíz del Monorepo. El archivo [`.gitignore`](file:///c:/basesDatos/mediqueue/.gitignore) global está programado para bloquear su rastreo por Git. Jamás desactives este filtro.

### 4. Nombres de Variables Estándar
Todos los microservicios deben mapear sus dependencias externas con la misma nomenclatura de variables de entorno en sus archivos de propiedades para facilitar el despliegue en la nube:

| Variable | Propósito | Valor por defecto (Local) |
|----------|-----------|---------------------------|
| `DB_URL` | Endpoint JDBC de PostgreSQL | `jdbc:postgresql://localhost:5432/{db_plural}` |
| `DB_USER` | Usuario de PostgreSQL | `mediqueue` |
| `DB_PASSWORD` | Contraseña de PostgreSQL | `mediqueue` |
| `REDIS_PASSWORD` | Contraseña del caché Redis | `redis123` |
| `RABBITMQ_USER` | Usuario del Broker de Mensajería | `mediqueue` |
| `RABBITMQ_PASS` | Contraseña de RabbitMQ | `rabbit123` |
| `JWT_SECRET` | Clave secreta para firmar tokens JWT | `change-me-in-production` |

### 5. Fallbacks Seguros para Producción
En los archivos de propiedades de producción (o perfiles como `prod`), **evita colocar valores por defecto para variables confidenciales**. De esta forma, si el orquestador en la nube falla al inyectar las variables, el servicio fallará al arrancar inmediatamente en lugar de usar una contraseña por defecto insegura.

---

## Auditoría Continua y Prevención de Fugas

Se recomienda ejecutar herramientas automáticas de escaneo antes de publicar commits en repositorios públicos.

### Escaneo con Gitleaks (Local)

Gitleaks es una herramienta SAST sumamente efectiva para detectar contraseñas e identificadores de nube expuestos en la historia de Git.

```bash
# Ejecutar un escaneo completo local del historial de commits antes de publicar
gitleaks detect --verbose

# Escanear cambios no commiteados en el espacio de trabajo actual
gitleaks protect --verbose
```

### Configuración de Pre-Commit Hooks (Husky)

Puedes bloquear la creación de commits que contengan secretos en tu máquina instalando hooks de Git automatizados:

```bash
# Ejecutar en la raíz del proyecto para pre-requisitos
npm install husky --save-dev
npx husky init

# Agregar el comando de protección de Gitleaks al pre-commit hook
echo "gitleaks protect --verbose" > .husky/pre-commit
```
