# 🔍 Verificación de binarios — Cliente WoW 1.12.1

[English](binary-verification.md) | **Español**

> **Análisis de superficie completa de un cliente no confiable antes de su uso en el laboratorio.**
>
> El cliente de WoW 1.12.1 no se distribuye por canales oficiales; las copias que
> circulan provienen de la comunidad y constituyen software de procedencia no
> verificada. Antes de ejecutarlo —y antes de distribuirlo a otros usuarios— se
> realizó un triage de seguridad completo sobre todos sus binarios.

---

## 🎯 Metodología

El análisis siguió una cadena de diligencia de cuatro etapas, escalando el nivel
de profundidad solo donde la evidencia lo justificaba:

1. **Inventario y hashing** — cálculo del SHA-256 de **todos** los ejecutables y
   librerías (`.exe`, `.dll`) del cliente.
2. **Análisis estático** — verificación de cada hash contra VirusTotal.
3. **Análisis dinámico** — para los binarios con detecciones, revisión del
   comportamiento en sandbox (red, persistencia, procesos, archivos).
4. **Verificación cruzada** — comparación de hashes contra un segundo cliente
   1.12.1 de fuente independiente para confirmar integridad (original vs. modificado).

### Comando de hashing

```powershell
Get-ChildItem -Recurse -Include *.exe,*.dll | Get-FileHash -Algorithm SHA256 | Format-List
```

![Inventario de hashes](binary-hash-inventory.png)

---

## 📊 Etapa 1-2: Inventario y análisis estático (cliente SoloCraft 1.12.1)

| # | Archivo | Tipo | SHA-256 | VirusTotal | Resultado |
|---|---|---|---|---|---|
| 1 | `WoW.exe` | Ejecutable principal | `B4756D38…B28D2DC7` | 0/71 | ✅ Limpio |
| 2 | `BackgroundDownloader.exe` | Downloader (Blizzard) | `588D507D…DB10DE27` | 0/71 | ✅ Limpio |
| 3 | `Repair.exe` | Reparador (Blizzard) | `52D4CB0B…567B5F855` | 0/71 | ✅ Limpio |
| 4 | `dbghelp.dll` | Debug helper (objetivo común de hijacking) | `72877FB0…52F0B` | 0/71 | ✅ Limpio |
| 5 | `DivxDecoder.dll` | Códec de cinemáticas | `ED34D37B…9915A5` | 1/71 | ⚠️ Falso positivo |
| 6 | `fmod.dll` | Motor de audio | `1E08DA16…383B22` | 1/70 | ⚠️ Falso positivo |
| 7 | `ijl15.dll` | Intel JPEG Library | `334AA12F…404E43A` | 0/70 | ✅ Limpio |
| 8 | `Scan.dll` | Componente del repack (scanner) | `AA5FFB5D…CE09F1` | 2/70 | ⚠️ Falso positivo (análisis ampliado) |
| 9 | `unicows.dll` | Unicode layer (legacy) | `22F23CC6…D72E56E` | 0/71 | ✅ Limpio |

### Interpretación de las detecciones

Las 3 detecciones siguen un patrón internamente consistente que apunta a
**falsos positivos heurísticos**, no a malware:

- **`DivxDecoder.dll` (1/71)** y **`fmod.dll` (1/70)**: únicamente **Cynet**, con
  la etiqueta genérica de Machine Learning *"Malicious (score: 100)"*. Sin familia
  de malware identificada. Ambos son componentes legacy de manipulación de
  audio/video (2004-2006), que disparan modelos de ML por su acceso de bajo nivel a memoria.
- **`Scan.dll` (2/70)**: Cynet (ML genérico) + Skyhigh (`BehavesLike.Win32.Trojan`,
  detección **comportamental**, no de firma). Empaquetado con **UPX**. Requirió
  análisis dinámico (ver Etapa 3).

> **Criterio aplicado:** una detección heurística aislada, sin familia de malware
> nombrada, en un binario legacy conocido, con la mayoría de los motores de
> referencia (Microsoft, Kaspersky, BitDefender, ESET, CrowdStrike) reportando
> limpio, se clasifica como falso positivo justificado.

---

## 🔬 Etapa 3: Análisis dinámico de `Scan.dll`

Por ser el binario con mayor número de detecciones y comportamiento "trojan-like",
se revisó su detección y su ejecución en sandbox.

![VT Scan.dll detección](vt-scan-detection.png)

| Vector observado | Hallazgo | Lectura |
|---|---|---|
| **Red (C2)** | Únicamente strings `upx.sf.net` / `upx.sourceforge.net` | Firma del empaquetador UPX en memoria — **no son conexiones C2**. Cero tráfico saliente sospechoso. |
| **Persistencia** | Ninguna clave de autostart (`Run`, servicios) | Solo claves de telemetría/compatibilidad de Windows. |
| **Procesos** | `rundll32`, `WerFault.exe`, dumps en `…\WER\…` | Andamiaje del sandbox + crash del DLL al ejecutarse fuera de contexto. No es actividad del binario. |
| **Payloads** | Ningún ejecutable nuevo dropeado | Solo artefactos de Windows Error Reporting. |

![VT Scan.dll comportamiento](vt-scan-behavior.png)

**Conclusión del análisis dinámico:** sin red C2, sin persistencia, sin payloads.
Comportamiento coherente con un módulo scanner/anti-cheat empaquetado con UPX que
dispara heurísticas comportamentales, **no con malware activo**.

---

## 🔗 Etapa 4: Verificación cruzada (cliente RetroWoW 1.12.1)

Para confirmar que los binarios son **originales y no modificados**, se compararon
los hashes contra un segundo cliente 1.12.1 de fuente independiente (RetroWoW).

| Archivo | SoloCraft | RetroWoW | ¿Idéntico? |
|---|---|---|---|
| `WoW.exe` | `B4756D38…` | `B4756D38…` | ✅ Sí |
| `dbghelp.dll` | `72877FB0…` | `72877FB0…` | ✅ Sí |
| `DivxDecoder.dll` | `ED34D37B…` | `ED34D37B…` | ✅ Sí |
| `fmod.dll` | `1E08DA16…` | `1E08DA16…` | ✅ Sí |
| `ijl15.dll` | `334AA12F…` | `334AA12F…` | ✅ Sí |
| `Repair.exe` | `52D4CB0B…` | `52D4CB0B…` | ✅ Sí |
| `unicows.dll` | `22F23CC6…` | `22F23CC6…` | ✅ Sí |
| `Scan.dll` | `AA5FFB5D…` | `4D83FD76…` | ❌ **Distinto** |

**Hallazgo clave:** los 7 componentes core de Blizzard tienen hashes SHA-256
**idénticos** entre dos repacks independientes. Es prueba criptográfica de que son
los binarios originales de Blizzard, sin modificar — si alguno hubiera sido
trojanizado en una copia, su hash diferiría del de la otra fuente.

El único divergente, `Scan.dll`, **no es un componente de Blizzard** sino propio de
cada empaquetado, lo que explica por qué no coincide.

### Nota sobre `WowError.exe` (exclusivo de RetroWoW)

El cliente RetroWoW incluye además `WowError.exe` (`2A3FD716…`), ausente en
SoloCraft. Detección: **1/67 (MaxSecure: `Trojan.Malware.300983.susgen`)**. El
sufijo `.susgen` = *suspicious generic*, MaxSecure es un motor de baja reputación, y
el binario está empaquetado con **Armadillo**. Es el manejador de crashes legítimo
de WoW; la detección es un falso positivo por packing. No se utiliza en el despliegue.

---

## ✅ Conclusión y decisión de despliegue

Los **7 componentes core de Blizzard** fueron verificados como originales y sin
modificar (hashes idénticos entre dos fuentes independientes), con análisis estático
limpio o falsos positivos heurísticos justificados.

Se identificaron dos componentes accesorios con detecciones heurísticas aisladas
(`Scan.dll` 2/70, `WowError.exe` 1/67), ambos empaquetados (UPX / Armadillo) y sin
familia de malware identificada. El análisis dinámico de `Scan.dll` no reveló
comportamiento malicioso.

**Decisión:** se utiliza el cliente SoloCraft 1.12.1 como base, **excluyendo el
`Scan.dll`** del directorio de despliegue. Dicho componente no es necesario para la
conexión al servidor VMaNGOS, por lo que su exclusión elimina la única superficie no
verificable contra un binario original — minimizando el riesgo residual sin afectar
la funcionalidad.

---

## 🖼️ Verificación de versión

Build del cliente confirmado: **1.12.1 (5875)**, coincidiendo con la imagen del
servidor (`vmangos-server:5875`).

![Versión del cliente](client-version-login.png)

---

## 🧠 Skills demostradas

- Triage de malware estructurado (estático → dinámico → verificación de integridad)
- Interpretación crítica de resultados de antivirus (falsos positivos vs. amenazas reales)
- Análisis de comportamiento en sandbox
- Verificación de integridad por hash criptográfico
- Toma de decisiones de seguridad fundamentada (reducción de superficie no verificable)

---

*Parte del lab de ciberseguridad — validación de software no confiable previo a su ejecución y distribución.*
