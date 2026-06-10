# Secure Software Factory

Pipeline DevSecOps multicapa con dos branches: una con vulnerabilidades intencionales que el pipeline bloquea, y otra con todo remediado donde los gates pasan.

| Branch | Estado |
|---|---|
| `vulnerable-demo` | [![Vulnerable](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml/badge.svg?branch=vulnerable-demo)](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml) |
| `remediated-demo` | [![Remediated](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml/badge.svg?branch=remediated-demo)](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml) |

---

## Pipeline

```
① pytest            tests unitarios
② Gitleaks          secretos en codigo e historial
③ Semgrep           analisis estatico (SAST)
④ Checkov           configuracion de Terraform
⑤ Trivy FS          CVEs en dependencias
   Trivy imagen     CVEs en la imagen Docker
⑥ Conftest + OPA    politicas propias en Rego
⑦ Anchore/Syft      SBOM en CycloneDX
⑧ cosign            firma keyless de la imagen en GHCR
⑨ Security gate     bloquea el build si algo falla
```

Los scans corren con `continue-on-error: true` para que todos reporten aunque alguno falle. El gate final agrega los outcomes y es el unico que bloquea.

---

## Hallazgos y remediaciones

| Herramienta | vulnerable-demo | remediated-demo |
|---|---|---|
| Gitleaks | Credenciales AWS en el codigo | Variables de entorno en runtime |
| Semgrep | SQL injection por concatenacion | Queries parametrizadas con `?` |
| Checkov | S3 publico, sin cifrado, IAM `Action:*`, SG `0.0.0.0/0` | KMS, versionado, IAM acotado, SG RFC1918 |
| Trivy FS | Dependencias con CVEs HIGH/CRITICAL | Versiones pineadas sin CVE |
| Trivy imagen | Paquetes vulnerables en el contenedor | `pip install --upgrade setuptools` en Dockerfile |
| Conftest Terraform | IAM wildcard, S3 publico, ingress abierto | Politicas Rego pasan |
| Conftest Dockerfile | App como root | Usuario `appuser` sin privilegios |

---

## Threat model

**App.** Tres vectores concretos: credencial de AWS en el repo (acceso a buckets con KYC o tablas de clientes), SQL injection en `/customers/search` sin autenticacion (lectura de toda la tabla), y contenedor como root (si hay un bug explotable en uvicorn, el atacante llega con privilegios al host).

**Pipeline.** Las actions se referencian por tag, no por SHA. Si comprometen la cuenta del mantenedor y mueven el tag, el proximo run ejecuta codigo malicioso con acceso a `secrets.GITHUB_TOKEN`. La solucion es pinear por commit SHA y dejar que Dependabot actualice los bumps. Ademas, sin branch protection rules cualquier developer puede hacer push directo a main saltandose los gates.

---

## Por que estas herramientas

**Semgrep** sobre Bandit porque Bandit solo cubre Python. El stack va a crecer y cambiar de herramienta SAST a mitad del camino es peor que arrancar con algo poliglota. El trade-off es que `p/default` genera ruido; en produccion se migraria a reglas custom de EFEX.

**Checkov** sobre tfsec porque cubre mas frameworks desde un solo tool y las excepciones con `#checkov:skip` quedan visibles en el diff del PR, no escondidas en un archivo de config separado.

**Trivy** sobre Snyk porque Snyk tiene limites de API en el tier gratuito que se vuelven problema con varios equipos. Un detalle no obvio: `python:3.11-slim` incluye `jaraco.context` y `wheel` vendorizados dentro de `setuptools/_vendor/`. Trivy los detecta con CVEs aunque esten pineados en `requirements.txt`. El fix es actualizar setuptools directamente en el Dockerfile.

**OPA/Conftest** para politicas propias de EFEX que no existen en ningun ruleset generico: ningun SG abre puertos fuera de RFC1918, ningun IAM con wildcard en Action o Resource.

**Gitleaks** sobre la deteccion nativa de GitHub porque GitHub detecta despues del push. Para IFPE no alcanza: el secreto puede haber llegado a los logs del runner antes de que llegue la alerta.

---

## Mapeo a IFPE y SOC 2

| Control | SOC 2 | IFPE |
|---|---|---|
| Gitleaks | CC6.1 acceso logico a credenciales | Proteccion de datos de pago y NPI |
| Semgrep | CC7.1 vulnerabilidades en desarrollo | Art. 52 seguridad en el ciclo de desarrollo |
| Checkov | CC6.6 perimetro, CC6.7 cifrado en reposo | Controles de infraestructura cloud |
| Trivy | CC7.1 inventario y vulnerabilidades | Gestion de vulnerabilidades en terceros |
| OPA/Conftest | CC5.2 controles por automatizacion | Politicas documentadas y ejecutables |
| SBOM | CC7.1 inventario para auditoria | Visibilidad sobre componentes de software |
| cosign | CC7.2 integridad del artefacto | Garantia de que la imagen en prod es la que escaneo el pipeline |
| SARIF | CC4.1 monitoreo con evidencia | Trazabilidad de controles por build |

Los artifacts SARIF y SBOM son la evidencia auditable por build. En produccion se archivarian por al menos un año en S3 con Object Lock o un SIEM, no los 90 dias por default de GitHub Actions.

---

## Pendiente para produccion

- Provenance SLSA nivel 2 completo (cosign keyless ya implementado, falta el attestation de build)
- Pinear las actions por SHA completo en lugar de tag
- Branch protection con status checks requeridos
- DAST contra el servicio levantado
- Pre-commit hooks para que Gitleaks corra antes del push

---

## Rollout a 5 equipos

Dos semanas en modo observacion primero: el pipeline reporta pero no bloquea. El Platform team clasifica con cada squad que es real y que es falso positivo. Despues se activa el bloqueo solo para lo que ya tiene solucion. Las excepciones son un PR al repo de politicas que aprueba Security, no un comentario en el codigo.

Si un developer tarda mas de 30 minutos resolviendo un hallazgo, el problema es la herramienta o la politica, no el developer.

---

## Correr localmente

```bash
pip install -r app/requirements.txt
pytest app/tests
uvicorn app.main:app --reload
```

```bash
docker build -t efex-demo .
docker run -p 8000:8000 efex-demo
```

```bash
cd terraform
terraform init
terraform plan -refresh=false
```
