# Architecture Decision Records (ADRs)

Decisiones arquitectónicas importantes del proyecto. Cada ADR documenta el contexto, decisión, y consecuencias de una decisión significativa.

---

## Cómo Agregar una ADR

1. Crea un archivo `AAAA-{numero}-{titulo-en-kebab-case}.md` en esta carpeta
2. Sigue el formato de plantilla abajo
3. Agrégalo a la tabla de contenidos
4. Actualiza [`docs/DOCUMENTATION-INDEX.md`](../DOCUMENTATION-INDEX.md)

### Formato de Nombrado

```
docs/architecture/AAAA-001-usar-outbox-pattern.md
docs/architecture/AAAA-002-seleccionar-rabbitmq-para-messaging.md
```

---

## Plantilla de ADR

```markdown
# ADR-{numero}: {Título}

**Status**: Proposed | Accepted | Deprecated | Superseded  
**Date**: YYYY-MM-DD  
**Participants**: [Nombres de participantes en la decisión]

## Context

Explica la situación, problema, o trigger que lleva a esta decisión.

## Decision

La decisión que se tomó y por qué.

## Rationale

Razonamiento detallado para la decisión.

## Consequences

**Positivas**: Qué ganancias trae
**Negativas**: Qué tradeoffs aceptamos
**Neutras**: Observaciones

## Alternatives Considered

- Alternativa 1: [descripción breve]
- Alternativa 2: [descripción breve]

## Related Decisions

- ADR-XXX: [decisión relacionada]

## References

- [Link a documentación relevante]
- [Papers, articles, etc.]
```

---

## ADRs Actuales

*Ninguno documentado aún. Próximas decisiones arquitctónicas deben ser registradas aquí.*

### Ejemplo: ADR-001 (Plantilla Llena)

```markdown
# ADR-001: Usar Patrón Outbox para Consistencia Eventual

**Status**: Accepted  
**Date**: 2026-05-06  
**Participants**: Architecture Team

## Context

En sistemas distribuidos con microservicios, necesitamos garantizar que:
- Los cambios se persisten en nuestra BD
- Los eventos se publican a otros servicios
- NO quedamos inconsistentes si uno de los dos falla

## Decision

Implementar el patrón Outbox:
1. Todos los cambios en el dominio se guardan en BD
2. Eventos se guardan en tabla `outbox_events` como PARTE de la transacción
3. Un proceso asíncrono (relay) envía eventos a RabbitMQ
4. Eventos se marcan como `published = true` después

## Rationale

- **Garantía transaccional**: Si falla la persistencia, TODO se rollback (entidad + evento)
- **Resiliencia**: Si RabbitMQ no está disponible, el relay reintenta después
- **Auditoría**: Todos los eventos quedan guardados en BD

## Consequences

**Positivas**:
- Consistencia eventual garantizada
- Resiliencia ante fallos de RabbitMQ
- Auditoría completa de eventos

**Negativas**:
- Complejidad adicional (tabla outbox, relay process)
- Latencia: evento se envía después de commit

## Alternatives Considered

1. Enviar eventos directamente a RabbitMQ en la transacción
   - Riesgo: si falla RabbitMQ, la transacción falla y se rollback TODO
2. Polling BD para cambios (Change Data Capture)
   - Complejidad: requiere infraestructura CDC (Debezium, etc.)
3. Event sourcing
   - Complejidad mayor; overkill para este proyecto

## References

- [Outbox Pattern - Chris Richardson](https://microservices.io/patterns/data/transactional-outbox.html)
```

---

## Checklist para Nueva ADR

- [ ] Archiva con formato `AAAA-{numero}-{titulo}.md`
- [ ] Incluye todas las secciones de la plantilla
- [ ] Status es uno de: Proposed, Accepted, Deprecated, Superseded
- [ ] Documento es auto-contenido (no asume contexto externo)
- [ ] Incluye alternativas consideradas
- [ ] Consecuencias son claras (positivas, negativas, neutras)
- [ ] Referencias están en el documento

---

**Última actualización**: Mayo 2026  
**Versión**: 1.0
