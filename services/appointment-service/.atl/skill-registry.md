# Skill Registry

## Active Skills

| Name | Source | Trigger |
|------|--------|---------|
| java-coding-standards | `.agents/skills/java-coding-standards/SKILL.md` | When writing or reviewing Java code in Spring Boot projects, enforcing conventions, or structuring layout. |
| java-docs | `.agents/skills/java-docs/SKILL.md` | When writing or reviewing Javadoc comments. |
| java-springboot | `.agents/skills/java-springboot/SKILL.md` | When developing Spring Boot applications, setting up projects, writing controllers/services/repositories. |
| security-privacy | `.agents/skills/security-privacy/SKILL.md` | ALWAYS ACTIVE. When generating code, configuring the environment, or advising the user, to prevent exposing sensitive data. |

## Compact Rules

### security-privacy
- ZERO SECRETS IN CODE. NEVER hardcode passwords, API keys, JWT secrets, or local paths.
- Mandatory use of environment variables (e.g., `${DB_PASSWORD}`) and `.env` files.
- Ensure `.env` and private keys are ignored in `.gitignore`. Warn the user if credentials are exposed.

### java-coding-standards
- Prefer clarity over cleverness; immutable by default (use records/final).
- PascalCase for Classes/Records; camelCase for Methods/fields; UPPER_SNAKE_CASE for Constants.
- Return Optional from find methods; use stream pipelines instead of loops for simple transformations.
- Create domain-specific exceptions; avoid catching generic Exception.
- Avoid magic numbers and static mutable state. Use Dependency Injection.

### java-docs
- Public and protected members must have Javadoc comments.
- Start description with a concise sentence ending in a period.
- Use `@param`, `@return`, `@throws`, `@see`, `@since`. Use `{@code }` for inline snippets.

### java-springboot
- Use constructor-based injection for required dependencies with `private final`.
- Organize code by feature/domain (not purely by layer).
- DTOs for web layer; avoid exposing JPA entities directly. Validate DTOs with JSR 380.
- `@Transactional` at service method level.
- Handle errors globally via `@ControllerAdvice`.
- Test using JUnit 5, Mockito, `@WebMvcTest`, `@DataJpaTest`.
