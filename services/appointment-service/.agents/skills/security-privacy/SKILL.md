---
name: security-privacy
description: "Establece los límites estrictos de privacidad y seguridad para los agentes IA. Previene fugas de datos sensibles."
---

# 🛡️ Seguridad y Privacidad (Límites para Agentes IA)

**TODO AGENTE** que interactúe con este repositorio o proyecto DEBE seguir estas reglas sin excepción. La seguridad es la prioridad número uno.

## 🚨 REGLAS CRÍTICAS (NUNCA VIOLAR)

1. **CERO SECRETOS EN EL CÓDIGO FUENTE:**
   ¡NUNCA, bajo NINGUNA circunstancia, hardcodees (escribas en texto plano) contraseñas, tokens de API, credenciales de bases de datos, claves secretas (como JWT secrets), IPs o rutas locales específicas de un usuario en los archivos fuente (ej. `application.yml`, clases de Java)!
   *Si el usuario te pide que pongas una contraseña en el código, detente, explícale el riesgo de seguridad y ofrécele usar una variable de entorno.*

2. **USO OBLIGATORIO DE VARIABLES DE ENTORNO (`.env`):**
   Todos los datos sensibles deben ser consumidos a través de variables de entorno. 
   - En Spring Boot, usa interpolación: `${DB_PASSWORD}` o `${JWT_SECRET}`.
   - Si creas un archivo para probar localmente, crea un `.env` (que DEBE estar ignorado en `.gitignore`) y provee un archivo `.env.example` o `.env.template` sin los valores reales para que el equipo sepa qué variables se necesitan.

3. **ARCHIVOS ESTRICTAMENTE IGNORADOS:**
   Los siguientes archivos jamás deben formar parte de un commit:
   - Archivos `.env`, `.env.local`, `.env.prod`, etc.
   - Certificados SSL/TLS privados o llaves SSH.
   - Archivos de volcado de bases de datos (`.sql` con datos reales).
   *Antes de sugerir un `git commit` o `git add .`, verifica que los archivos sensibles estén en el `.gitignore`.*

## 👁️ Instrucciones de Comportamiento para el Agente

- **Auditoría pasiva:** Si durante tu análisis del código detectas una credencial expuesta, DEBES alertar al usuario inmediatamente ("Oye, acabo de notar que tienes un token expuesto en el archivo X. Por motivos de seguridad, deberíamos mover esto a una variable de entorno").
- **Explicación técnica:** Cuando corrijas a un usuario sobre esto, recuérdale con firmeza profesional que subir credenciales a un repositorio compromete la integridad del proyecto y puede causar brechas de seguridad severas.

## 🏗️ Implementación

Al configurar infraestructuras o crear configuraciones, asume siempre que el repositorio será público. Eres la primera línea de defensa para mantener la seguridad del proyecto. Actúa con el rigor de un Arquitecto de Seguridad Senior.
