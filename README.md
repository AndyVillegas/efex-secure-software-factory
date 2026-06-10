# Secure Software Factory

Dos branches. Una tiene las vulnerabilidades típicas que llegan a producción cuando no hay controles: secreto hardcodeado, SQL injection, dependencias con CVEs, infraestructura pública sin cifrado y el contenedor corriendo como root. La otra tiene todo eso arreglado y el pipeline pasa completo.

| Branch | Estado |
|---|---|
| `vulnerable-demo` | [![Vulnerable](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml/badge.svg?branch=vulnerable-demo)](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml) |
| `remediated-demo` | [![Remediated](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml/badge.svg?branch=remediated-demo)](https://github.com/AndyVillegas/efex-secure-software-factory/actions/workflows/devsecops.yml) |

---

## Pipeline

```
① pytest           tests unitarios
② Gitleaks         secretos en código e historial
③ Semgrep          análisis estático (SAST)
④ Checkov          configuración de Terraform
⑤ Trivy FS         CVEs en dependencias Python
   Trivy imagen    CVEs en la imagen Docker
⑥ Conftest + OPA   políticas propias en Rego
⑦ Anchore/Syft     SBOM en formato CycloneDX
⑧ Security gate    bloquea el build si algo falla
```

Todos los scans tienen `continue-on-error: true` para que si uno falla, los demás sigan corriendo y generen sus reportes. El gate final es el único que bloquea, y revisa el outcome de cada step, no el exit code directo. Así un falso positivo en Semgrep no mata el pipeline antes de que Trivy pueda correr.

---

## Lo que detecta cada branch

### `vulnerable-demo`

| Herramienta | Hallazgo |
|---|---|
| Gitleaks | Credenciales AWS en el código |
| Semgrep | SQL injection por concatenación de strings |
| Checkov | S3 público sin cifrado ni versionado, IAM con `Action: *`, SG abierto a `0.0.0.0/0` |
| Trivy FS | Dependencias con CVEs HIGH/CRITICAL |
| Trivy imagen | Paquetes vulnerables en el contenedor |
| Conftest Terraform | IAM wildcard, S3 público, ingress sin CIDR restringido |
| Conftest Dockerfile | App corriendo como root |

### `remediated-demo`

| Herramienta | Cambio |
|---|---|
| Gitleaks | Credenciales eliminadas del código, se inyectan como variables de entorno |
| Semgrep | Queries parametrizadas con `?` |
| Checkov | S3 con KMS, versionado, access logging y acceso público bloqueado. IAM acotado a acciones y ARN específicos. SG con ingress solo RFC1918 y egress solo HTTPS |
| Trivy FS | Dependencias pineadas a versiones sin CVE |
| Trivy imagen | Se actualiza setuptools en el Dockerfile. Los paquetes vulnerables (`jaraco.context` y `wheel`) estaban vendorizados dentro de setuptools en la imagen base, no en site-packages, así que pinarlos en requirements.txt no servía |
| Conftest Terraform | IAM acotado, S3 bloqueado, CIDRs privados en SG |
| Conftest Dockerfile | Usuario `appuser` sin privilegios |

---

## Threat model

### La app

El servicio maneja CLABEs, estatus KYC y pagos. Tres vectores concretos:

El primero es la credencial en el repo. Un developer sube una key de AWS en el código, esa key tiene acceso a buckets con documentos KYC o tablas de clientes. No hace falta un atacante sofisticado, hay bots que hacen scraping de repos de GitHub buscando exactamente eso.

El segundo es la SQL injection en `/customers/search`. El endpoint vulnerable arma la query concatenando el email del request. Cualquier caller puede hacer `' OR '1'='1` y leer toda la tabla de clientes sin autenticarse.

El tercero es el contenedor como root. Si hay un bug explotable en uvicorn o alguna dependencia, el atacante escapa del contenedor con privilegios de root en el host. Bajar a un usuario sin privilegios no elimina el riesgo pero sube el costo.

Fuera del scope de este demo: no hay rate limiting, no hay autenticación en ninguna ruta y la validación de inputs solo cubre el monto del pago.

### Supply chain

Las actions del pipeline se referencian por tag (`gitleaks/gitleaks-action@v2`, `aquasecurity/trivy-action@v0.24.0`). Un tag puede moverse. Si comprometen la cuenta del mantenedor y apuntan el tag a código malicioso, el próximo run ejecuta ese código con acceso a `secrets.GITHUB_TOKEN`. La solución correcta es pinear por commit SHA y dejar que Dependabot actualice los bumps.

Trivy detecta CVEs publicados, pero no código malicioso recién subido a PyPI sin CVE todavía. El SBOM cubre eso: si pasa algo en producción, hay un registro exacto de qué versión de qué paquete estaba instalada en ese build.

Sin branch protection rules, cualquier developer con acceso de escritura puede hacer push directo a main sin pasar el pipeline. Los gates son obligatorios solo si hay status checks requeridos configurados en la rama.

---

## Por qué estas herramientas

**Semgrep sobre Bandit.** Bandit solo cubre Python. El stack va a crecer y cambiar de herramienta SAST a mitad del camino es peor que arrancar con algo políglota. Semgrep corre las mismas reglas en Python, Go, JavaScript y Terraform HCL. El trade-off es que `p/default` genera ruido en codebases grandes. En producción se migraría a `p/python` más reglas custom de EFEX: cualquier string que llegue directo a una query SQL, cualquier log que incluya `clabe` o `kyc_status`.

SonarQube tiene más features pero requiere servidor persistente, más costo y un punto de falla para un control crítico. SonarCloud cuesta dinero. Para este estadio Semgrep OSS en CI es suficiente.

**Checkov sobre tfsec.** Los dos hacen lo mismo para Terraform, pero Checkov cubre más frameworks desde un solo tool (Terraform, Kubernetes, Dockerfile). Lo más útil es el `#checkov:skip` inline: las excepciones quedan visibles en el diff del PR en lugar de escondidas en un archivo de config separado. Para SOC 2 eso importa, el auditor puede ver en el historial cuándo se aprobó la excepción y por qué.

**Trivy sobre Snyk.** Snyk tiene límites de API en el tier gratuito que se vuelven problema con varios equipos desplegando continuamente. Grype de Anchore es bueno pero para el scan de imagen necesita Syft como paso separado. Trivy hace filesystem scan, image scan y SBOM en una sola herramienta.

Un detalle no obvio: `python:3.11-slim` incluye `jaraco.context` y `wheel` vendorizados dentro de `setuptools/_vendor/` con su propio dist-info. Trivy los detecta como paquetes instalados y reporta CVEs contra ellos aunque estén pineados en `requirements.txt`. El fix es `pip install --upgrade setuptools` en el Dockerfile.

**OPA/Conftest para políticas propias.** Checkov cubre misconfigs genéricas de AWS. Lo que no cubre son reglas específicas de EFEX: ningún SG abre puertos fuera de RFC1918, ningún IAM con wildcard en Action o Resource. Esas no existen en ningún ruleset genérico porque son decisiones de negocio. Rego permite definirlas en código, versionarlas y revisarlas en PR como cualquier otro cambio.

**Gitleaks sobre la detección nativa de GitHub.** GitHub detecta secretos después del push. Para IFPE eso no alcanza: el secreto puede haber llegado a los logs del runner o a la caché de Actions antes de que llegue la alerta. Gitleaks corre justo después del checkout, antes de que cualquier otro step vea el código.

---

## Mapeo a IFPE y SOC 2

| Control | SOC 2 | IFPE |
|---|---|---|
| Gitleaks | CC6.1 acceso lógico a credenciales | Protección de datos de pago y NPI |
| Semgrep | CC7.1 detección de vulnerabilidades en desarrollo | Art. 52 seguridad en el ciclo de desarrollo |
| Checkov | CC6.6 protección de perímetro, CC6.7 cifrado en reposo | Controles de configuración de infraestructura cloud |
| Trivy | CC7.1 inventario de componentes y vulnerabilidades | Gestión de vulnerabilidades en software de terceros |
| OPA/Conftest | CC5.2 actividades de control por automatización | Políticas de seguridad documentadas y ejecutables |
| SBOM | CC7.1 inventario de componentes para auditoría | Visibilidad sobre componentes de software |
| SARIF artifacts | CC4.1 monitoreo con evidencia auditable | Trazabilidad de controles por build |

Los artifacts SARIF y SBOM son la evidencia concreta. Cada build a producción debería tener ambos archivados por al menos un año. GitHub Actions guarda 90 días por default; en producción se mandarían a S3 con Object Lock o un SIEM.

---

## Rollout a 5 equipos

El problema no es técnico. Es que cinco equipos tienen que aceptar un gate que puede bloquear sus deploys con un Lead Time objetivo de menos de una hora.

Lo que funciona es arrancar en modo observación dos semanas. El pipeline corre, reporta hallazgos, pero nada bloquea. Durante ese tiempo el Platform team se sienta con cada squad para clasificar qué es real, qué es falso positivo y qué necesita una excepción documentada. Después de las dos semanas se activa el bloqueo solo para lo que ya tiene solución. Los hallazgos nuevos bloquean de inmediato.

Las excepciones tienen que ser un proceso explícito. El `#checkov:skip` sirve para un recurso puntual, pero para excepciones que aplican a varios builds o equipos el mecanismo correcto es un PR al repo de políticas que aprueba Security. Ese PR queda en el historial con fecha, autor y razón.

La pregunta de fondo: si un developer tarda más de 30 minutos resolviendo un hallazgo de seguridad, el problema es la herramienta o la política, no el developer. El gate tiene que decir exactamente qué está mal y en qué línea. Si no puede hacer eso, va a generar fricción hasta que alguien con suficiente influencia lo apague.

---

## Artifacts por run

- `sbom-cyclonedx` SBOM en CycloneDX JSON de la imagen construida
- `terraform-plan-json` plan de Terraform en JSON, input a Conftest
- `checkov-sarif` hallazgos de Checkov en formato SARIF

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

Terraform corre en modo offline con credenciales dummy, no necesita cuenta de AWS.

```bash
cd terraform
terraform init
terraform plan -refresh=false
```
