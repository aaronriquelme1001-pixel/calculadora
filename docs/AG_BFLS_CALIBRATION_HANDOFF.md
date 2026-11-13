# AG-BFLS — handoff técnico para continuidad de IA

Actualizado: 2026-11-13  
Repositorio: `aaronriquelme1001-pixel/calculadora`  
Rama de trabajo obligatoria: `main`

## 1. Instrucciones de continuidad y límites del usuario

- Leer este documento y `README.md` antes de modificar código.
- Analizar el estado actual de `main` y sus commits; no asumir que resúmenes anteriores reflejan el HEAD actual.
- Todo cambio futuro debe quedar directamente en `main`. No crear ramas de trabajo ni dividir la solución.
- No generar APK/AAB aquí. El usuario genera la APK en su entorno separado.
- No hacer despliegues manuales ni publicar artefactos distintos de los flujos existentes.
- No declarar interoperabilidad física sin probar un sensor AG-BFLS real.
- No inventar IDs, credenciales, datos de anuncios, capacidades de firmware o resultados de hardware.
- Nunca registrar ni subir la credencial oficial de ocho bytes, claves, PIN, keystores o datos privados.
- Antes de modificar la EEPROM, respaldar los 100 slots y verificar rollback. No hacer pruebas de escritura sin autorización y sensor de banco.

## 2. Estado del producto

El repositorio contiene dos clientes que comparten el protocolo:

1. Calculadora web HTML/CSS/JavaScript: modelado 2D/3D de estanques, cálculo de volumen, importación/exportación de tablas y consola BLE experimental.
2. Aplicación Android Flutter en `fuel_master_pro/`: conexión BLE, telemetría, autenticación, importación de Excel/CSV y operaciones de memoria.

El objetivo es que nuestra aplicación importe una tabla oficial de calibración (Data/Level/Volume) y pueda transferirla al AG-BFLS de forma verificable, manteniendo compatibilidad con Fuel Master oficial.

## 3. Cambios existentes en la línea principal

### Protocolo y BLE

- Servicio GATT: `0000fff0-1212-efde-1523-785feabcd123`.
- Característica escritura: `0000fff1-1212-efde-1523-785feabcd123`.
- Característica notificaciones: `0000fff2-1212-efde-1523-785feabcd123`.
- Trama: `0C [LL] [ID2 ID1 ID0] [CMD] [DATA...] [CRC8]`.
- CRC-8 reflejado con polinomio `0x8C`.
- ID del sensor y Número de Serie (SN):
  - En el protocolo de tramas son exactamente 3 bytes: `[ID2, ID1, ID0]`.
  - El Número de Serie comercial (SN) impreso en la etiqueta del sensor y listado en Fuel Master oficial es el entero decimal de 24 bits:
    $$\text{SN} = (\text{byte}_0 \ll 16) \mid (\text{byte}_1 \ll 8) \mid \text{byte}_2$$
    Ejemplo: bytes `[0x0C, 0x52, 0x02]` corresponden a `SN: 807426`.
  - Para ingreso humano la aplicación admite indistintamente el SN decimal (ej. `807426`) o los 3 bytes en hexadecimal (ej. `0C:52:02`, `0C-52-02` o `78:24:15`).
- Manufacturer ID de anuncio conocido: `0xFF43` (AOOOG, 15 bytes) y `0xFFFF` (Universal/Dominator, 24 bytes), parseando ID, SN, batería (%), temperatura (°C) y frecuencia (Hz).
- Credencial: exactamente ocho bytes del fabricante (16 caracteres hexadecimales), sin valores por defecto.
- Comandos usados: `0x01` reinicio; `0x02` hibernación; `0x0D` parámetros; `0x10` punto vacío; `0x11` punto lleno; `0x12` autenticación; `0x14` telemetría; `0x15` lectura de bloque; `0x16` escritura de bloque; `0x19/0x1A` establecer/leer modo de salida.
- Las respuestas deben validarse por ID, comando, longitud y CRC. Los comandos de escritura requieren ACK de éxito.

### Consola BLE Web (Diseño Blanco Sobrio y Compacto)

- La consola web BLE (`#panelBleSensor`) está integrada en el sistema de diseño claro de la aplicación (`var(--bg-card): #ffffff`, `var(--border): #e2e8f0`).
- No utiliza recuadros oscuros ni cajas anidadas repetitivas; presenta una sola tarjeta blanca sobria con:
  1. Barra de cabecera con estado, SN, HEX, porcentaje de batería y botones de acción limpios.
  2. Franja horizontal de telemetría de perfil bajo en gris suave (`#f8fafc`).
  3. Área de control en dos columnas limpias (Calibración base izquierda; Tabla EEPROM y seguridad derecha).
- Búsqueda abierta unificada:
  - Tanto `🔍 Buscar Sensor` como `🌐 Todos` usan `acceptAllDevices: true` y `optionalServices: [SERVICE_UUID]`.
  - No se filtra por `manufacturerData`, nombre o UUID anunciado porque algunos AG-BFLS no exponen esos datos antes de emparejar.
  - La selección puede mostrar periféricos ajenos; la identidad se valida después por SN/ID y lectura GATT `0x1A`.

### Importación de calibración

- Formato canónico: `Data | Level | Volume`.
- Data se conserva como coordenada real del sensor y se mapea a `fixValue`.
- Level es uint16 en mm; Volume es float32 en litros.
- Importación Flutter: XLSX y CSV/TXT delimitado, encabezados reconocidos, columnas reordenadas, coma decimal, validación estricta.
- Reglas: 2–100 filas activas, origen 0/0/0, Data y Level estrictamente crecientes, Volume no decreciente, límites Data 0–5000, Level 0–65535, Volume 0–1.000.000 L.
- La tabla de referencia SHVS36 contiene 29 filas incluyendo origen; último punto Data=5000, Level=546 mm, Volume=249.2 L.
- No convertir datos inválidos a cero silenciosamente.
- Una tabla geométrica calculada no representa mediciones Data reales. No debe transferirse como tabla oficial si no tiene coordenadas Data reales importadas.

### Escritura y protección

- Memoria de 100 slots, 10 bloques de 10 filas, 8 bytes por fila.
- Antes de escribir, leer y respaldar los diez bloques y el modo de salida.
- Escribir un bloque, exigir ACK y leer de vuelta los 80 bytes exactos antes de avanzar.
- Verificar el modo litros `0x02` mediante lectura `0x1A`.
- Ante fallo, intentar restaurar todos los bloques y el modo original; reportar explícitamente si rollback no puede confirmarse.
- Flutter exige MTU negociado >= 91 para escritura.
- Web Bluetooth no expone un MTU negociado fiable; no prometer que la escritura larga funcionará en todos los navegadores/adaptadores.

## 4. Cambio de esta intervención: navegador no encontraba el sensor

### Causa de código identificada

La búsqueda web anterior utilizaba una lista restrictiva de filtros por nombre, UUID anunciado y manufacturer data. Un AG-BFLS que no publicara alguno de esos campos podía quedar fuera del selector, aunque estuviera anunciando BLE y fuera conectable. Además, la conexión dependía de `watchAdvertisements()`, API de soporte desigual.

### Corrección aplicada en `app.js`

- El selector ahora usa `requestDevice({ acceptAllDevices: true, optionalServices: [SERVICE_UUID] })`.
- Ya no se filtra el periférico por nombre, manufacturer ID o UUID anunciado.
- La selección la realiza el usuario en el selector nativo del navegador.
- `watchAdvertisements()` quedó como fuente opcional de ID; si no existe/no funciona, no bloquea descubrimiento ni GATT.
- Solo se aprende el ID de una trama espontánea `0x14` completa (22 bytes), CRC válido, ID no nulo y campos numéricos coherentes. Una trama de otro comando con CRC válido no establece identidad.
- Si no se obtiene ID, se solicita el ID real de la etiqueta/documentación sin valor predeterminado.
- Antes de permitir operaciones, se valida el ID con lectura de solo lectura `0x1A`; se exige respuesta correcta y modo 0, 1 o 2.
- Si el ID no se confirma, se desconecta. No se autentica ni se escribe.
- Se eliminó la extracción del ID desde el nombre Bluetooth, porque el nombre no es una fuente fiable del ID de protocolo.
- Los botones Buscar Sensor y Buscar Todos usan el selector abierto.

### Diagnóstico documentado

Consultar `docs/WEB_BLUETOOTH_DIAGNOSTICS.md` para requisitos, flujo, límites y pasos de diagnóstico.

Puntos esenciales:
- Web Bluetooth requiere HTTPS o localhost.
- Probar con Chrome/Edge actualizado en Chromium. Safari/iOS y Firefox no son plataformas soportadas para esta consola.
- `requestDevice` abre un selector controlado por navegador; no es un escáner continuo en segundo plano.
- `acceptAllDevices` elimina filtros de la aplicación, pero no puede mostrar un sensor apagado, fuera de alcance, no anunciando o no conectable.
- Cerrar Fuel Master oficial/otras apps que estén conectadas al mismo sensor antes de probar.
- Si el selector muestra el sensor pero no conecta GATT, verificar servicio FFF0 y características FFF1/FFF2.
- Si el selector no muestra nada incluso con búsqueda abierta, investigar sistema operativo, radio/adaptador BLE, driver, permisos y estado de advertising del sensor. El problema ya no es un filtro de nombre de nuestra app.

## 5. Validación automatizada del cambio BLE

- Commit de código/documentación validado: `c90f48ade2c73e8727cf02271c3eb7c7db952791`.
- GitHub Actions: https://github.com/aaronriquelme1001-pixel/calculadora/actions/runs/43473038669
- Job web: PASS (sintaxis `node --check app.js` y pruebas Node de protocolo/descubrimiento).
- Job Flutter: PASS (dependencias, análisis estático y pruebas unitarias).
- Esto valida software y regresiones automatizadas; no valida radio BLE ni sensor físico.

## 6. Pruebas añadidas

Nuevo archivo: `tests/ble-protocol.test.cjs`.

Pruebas:
- construcción y análisis de trama con ID de tres bytes;
- rechazo de CRC y longitudes inválidas;
- serialización de filas en little-endian y validación de rangos;
- verificación estática de búsqueda abierta sin filtros restrictivos;
- verificación de que advertisement monitoring sea opcional y el ID se confirme con lectura 0x1A.

Comando:
```bash
node --check app.js
node --test tests/*.test.cjs
```

GitHub Actions ahora ejecuta ambas verificaciones web además de Flutter analyze/test.

## 7. Límites que siguen pendientes

- No hay evidencia de que un AG-BFLS físico haya sido detectado o conectado por esta versión web.
- No se ha validado la conexión GATT real desde el navegador ni el comportamiento de la radio en el equipo del usuario.
- No se ha confirmado que todos los firmwares expongan FFF0/FFF1/FFF2 con estas UUID exactas.
- No se ha demostrado que la escritura web de 81 bytes (índice + 80 bytes) funcione en todos los navegadores y adaptadores.
- No se ha ejecutado todavía el ciclo de escritura/lectura/rollback en un sensor real.
- La compatibilidad con Fuel Master oficial debe probarse con importación/exportación real.
- La aplicación Flutter sigue siendo la ruta prioritaria para la primera prueba física, por su control del MTU.

## 8. Protocolo de prueba física cuando el usuario disponga del sensor

1. Cerrar Fuel Master oficial y otras conexiones.
2. Registrar navegador/versión, SO, adaptador BLE y firmware del sensor.
3. Comprobar que el sensor aparece en un escáner BLE independiente.
4. Probar el selector abierto web; anotar nombre mostrado y si aparece.
5. Seleccionar el sensor y confirmar descubrimiento GATT FFF0, FFF1 y FFF2.
6. Capturar el ID desde anuncio/trama o etiqueta. No adivinarlo.
7. Confirmar lectura 0x1A antes de autenticar.
8. Autenticar con credencial real de ocho bytes sin registrarla ni compartirla.
9. Leer los 10 bloques y guardar el backup original.
10. Importar SHVS36 y revisar 29 filas.
11. Escribir los 10 bloques, comparar lectura de retorno byte a byte.
12. Verificar modo litros 0x02 y telemetría.
13. Probar rollback controlado con una condición segura.
14. Comparar la misma tabla en Fuel Master oficial.
15. Adjuntar solo logs saneados; no subir credenciales.

## 9. Archivos importantes para continuar

- `app.js`: consola web, protocolo, conexión y operaciones BLE.
- `index.html`: interfaz web y controles de BLE.
- `fuel_master_pro/lib/services/aooog_ble.dart`: UUID, framing, CRC y parseo de anuncios Flutter.
- `fuel_master_pro/lib/services/aooog_manager.dart`: conexión GATT, MTU, autenticación, comandos y memoria.
- `fuel_master_pro/lib/services/calibration_table_codec.dart`: importación/validación de tabla.
- `tests/ble-protocol.test.cjs`: pruebas web del protocolo y del flujo de descubrimiento.
- `docs/WEB_BLUETOOTH_DIAGNOSTICS.md`: diagnóstico navegador BLE.
- `README.md`: mapa general del repositorio.

## 10. Archivos de referencia oficiales del fabricante

El repositorio conserva en `docs/reference/` los tres documentos y aplicaciones originales de AoooG como base inmutable de verificación técnica:
- `docs/reference/AG-BFLS_User_Manual.pdf` (1.5 MB): Manual de usuario oficial, instalación mecánica, conexión de cables y procedimiento de calibración física (puntos vacío y lleno).
- `docs/reference/AG-BFLS_Datasheet.pdf` (733 KB): Ficha técnica, precisión capacitiva, protocolo, señales y especificaciones eléctricas.
- `docs/reference/Fuel Master V0.1.4.apk` (57.6 MB): APK oficial del fabricante de referencia. No confundir con la APK de nuestra aplicación que se compila externamente.
- `docs/reference/README.md`: Resumen y hashes de integridad de los archivos de referencia.


---

## 11. Handoff — endurecimiento BLE e identificación SN (2026-11-13)

**Rama de trabajo:** `fix/ble-identification-auth-regression-2026-11-13`  
**Base:** `b77cc8e6672ccccb3aaf10e6dbb6ebc0f4d9f3bd`  
**Estado:** cambios implementados en rama aislada; no fusionados a `main`. No se hizo prueba física BLE.

### Problemas corregidos

1. **Búsqueda primaria demasiado restrictiva:** el botón Buscar Sensor utilizaba filtros manufacturerData `0xFF43` y `0xFFFF`; algunos AG-BFLS no exponen estos datos antes de conectarse. Ahora Buscar Sensor y Todos utilizan el selector abierto `acceptAllDevices: true`, con `optionalServices` FFF0. Se mantiene la identificación de protocolo después de seleccionar.
2. **Identidad aprendida desde cualquier trama:** antes bastaba una trama con CRC válido y un ID no nulo. Ahora solo se aprende el ID desde una trama `0x14` de exactamente 22 bytes, ID no nulo, temperatura dentro de rango y campos numéricos finitos/no negativos. Las notificaciones de otros comandos no pueden establecer identidad.
3. **Credencial:** se extrajo `parseBleCredential`; acepta exactamente 16 caracteres hexadecimales y genera ocho bytes. No guarda la cadena en el estado de sesión ni la registra. La autenticación sigue dependiendo del ACK exitoso `0x12`; ante fallo queda `isAuthenticated=false`.

### Pruebas de regresión añadidas

En `tests/ble-protocol.test.cjs`:
- parser de credencial: 8 bytes exactos, longitud inválida y caracteres no hex;
- telemetría: acepta estructura válida y rechaza comando distinto, longitud incorrecta, ID cero, NaN, frecuencia negativa y temperatura fuera de rango;
- guardas de `handleBleNotification`: no aprende identidad de una trama arbitraria;
- ambas entradas de búsqueda usan el selector abierto;
- autenticación valida credencial, envía exactamente ocho bytes y requiere ACK positivo.

Comandos locales de validación:
```bash
node --check app.js
node --test tests/*.test.cjs
```

### Estado de validación y límites

- No afirmar todavía que los tests pasan: deben ejecutarse en CI sobre el HEAD de esta rama.
- No afirmar que el navegador detecta el sensor físico: hace falta prueba con sensor real y adaptador BLE del usuario.
- Las pruebas nuevas son unitarias/estructurales sobre funciones puras y guardas de flujo; no son un E2E de Web Bluetooth ni sustituyen un ensayo GATT físico.
- No se ha autenticado, leído ni escrito EEPROM en hardware durante esta intervención.
- No se ha cambiado Flutter ni el protocolo del fabricante.
- No se han tocado credenciales, APK, producción ni despliegues.
- No fusionar a `main` hasta revisar CI, el diff y completar al menos una prueba física de descubrimiento + GATT + lectura `0x1A`. No hacer escrituras de EEPROM sin backup y autorización explícita.

### Próximos pasos para la siguiente IA

1. Ejecutar `node --check app.js` y `node --test tests/*.test.cjs`; corregir cualquier regresión.
2. Confirmar que GitHub Actions valida el HEAD de esta rama.
3. Revisar el diff completo, especialmente el orden conexión → notificaciones → ID → lectura `0x1A` → autenticación `0x12`.
4. Probar con un AG-BFLS físico: selector abierto, identificar por SN de etiqueta, conectar GATT, validar modo por `0x1A`, autenticar con credencial del fabricante sin registrarla.
5. Mantener cualquier prueba de escritura fuera del alcance hasta contar con autorización, backup de 100 slots y procedimiento de rollback.


---

## 12. Handoff — implementación contra el perfil público AG-BFLS (2026-11-13)

Este apartado **actualiza y reemplaza cualquier nota anterior** que dijera que no se modificó Flutter o que solo estaban cubiertos descubrimiento/autenticación.

### Cambios añadidos desde la sección 11

- Web `app.js`:
  - Decodificadores oficiales 0x0D, 0x14, 0x1B, 0x20, 0x21 y 0x26.
  - Comandos y controles UI para 0x04/05, 0x0A/0B, 0x0C, 0x20/21/22, 0x26 y 0x1B.
  - Validación central de payload por comando, longitud, rango e índice.
  - Guardas centrales de autenticación para 01, 02, 04, 0A, 0C, 10, 11 y 16.
  - Conversión de batería con `floor((code - 500) * 100 / 220)`, porcentaje modo 0 = salida / 100, y validación del byte reservado de 0x14.
  - Modos mm/L bloqueados hasta tener tabla del sensor validada.
  - Backup previo, escritura por 10 bloques, readback byte a byte y rollback ya existente preservados.
- Flutter:
  - Decodificadores de parámetros, versión, dirección BLE, formato de publicidad y coordenada 1B.
  - Validación central de payload y comandos protegidos.
  - Verificación de identidad por lectura 1A tras habilitar notificaciones.
  - Requisitos de ATT MTU: 90 para respuesta 15 y 91 para escritura 16.
  - Conversión de batería por floor y rechazo de telemetría 14 con reservado inválido.
  - Métodos de lectura/escritura con readback para potencia TX, intervalo, continuar tras reinicio y formato de publicidad.
- Pruebas:
  - `tests/ble-protocol.test.cjs`: decodificación 0D/14/1B/20/21/26, conversión batería, validación de payload y guards.
  - `fuel_master_pro/test/aooog_protocol_test.dart`: CRC, batería, estructuras 0D, coordenada, versión, address, advertising protocol y payloads.

### Restricción real de Web Bluetooth

Web Bluetooth no expone una API estándar para solicitar ni consultar el ATT MTU. La app web puede intentar la escritura completa de 88 bytes y manejar el error; no puede garantizar previamente que el MTU cumpla el requisito. Las respuestas 0x15 de 87 bytes requieren ATT MTU ≥90. Para lectura/escritura fiable de tabla, la ruta preferida es Flutter nativo, que solicita MTU 247 y comprueba los mínimos.

### Validación pendiente en hardware — no marcar como terminada

- CI ejecutado correctamente en el código HEAD `2a7d0197cb3919cf4e1b271db9068c2de28409e3`: run `43489968286`. Web: `node --check app.js` y `node --test tests/*.test.cjs` PASS. Flutter: `flutter pub get`, `flutter analyze` y `flutter test` PASS. El commit posterior que actualiza este handoff solo modifica documentación.
- La prueba física sigue pendiente: anuncio con SN correcto, conexión GATT, lectura 1A, autenticación 12, lectura 0D/14 y respaldo 15. No se ha realizado escritura EEPROM real.
- El navegador depende del MTU negociado por el sistema; si falla la transferencia 15/16, no reintentar automáticamente desde cero. Usar Flutter nativo o revisar el MTU.
- El comando 22 cambia el formato de publicidad; puede alterar cómo otras apps encuentran el sensor. Solo usar tras confirmación del técnico.
- No integrar a main hasta CI verde y prueba física de solo lectura. La prueba de escritura requiere backup y autorización explícita.

### Fuente de protocolo

`docs/AG_BFLS_PUBLIC_PROTOCOL_IMPLEMENTATION.md`  
`https://www.aooog.com/bluetooth-protocol.html`


## 13. Ajustes finales de consistencia de protocolo y UI (2026-11-13)

- Universal advertisement ahora valida el status actual `0x01` además de firma `3F 36 B4` y Type `5B`; el test cubre status inválido.
- AOOOG manufacturer data decodifica también el nibble de output mode y rechaza modos fuera de 0–2.
- Flutter conserva temperatura AOOOG con resolución de 1/8 °C (double), no la redondea en el parser.
- Flutter mantiene una sola suscripción a `scanResults`, la registra antes de iniciar scan y la cancela al terminar/desmontar o al conectar. La lista muestra `SN: id`, no remoteId/MAC.
- Flutter usa el modo de salida confirmado por GATT 1A/0D para mostrar % (output/100), mm o L; no etiqueta siempre como litros.
- Modos 1/2 requieren origen 0/0/0 y tabla completa válida con terminador sin huecos; se valida antes de cambiar modo.
- Web Bluetooth no tiene API estándar para consultar/solicitar MTU: no se usa un método no estándar. Los comandos 15/16 intentan transferencia y manejan error/rollback; Flutter nativo es la ruta fiable cuando el navegador/OS no negocia MTU suficiente.

---

## 14. Estado vigente después de integrar a main (2026-11-13)

**Esta sección es la referencia vigente y prevalece sobre instrucciones históricas anteriores que indicaban no integrar la rama.**

- PR #5 fue fusionado en `main`: https://github.com/aaronriquelme1001-pixel/calculadora/pull/5
- Merge commit: `f000e4d0d66dfb2c841848145004841c89780ca5`.
- Rama integrada: `fix/ble-identification-auth-regression-2026-11-13`, HEAD `25dd6ae936b29173afe12958bf3778d2328fca77`.
- Los dos checks de GitHub Actions sobre el HEAD del PR finalizaron en SUCCESS: validación web y análisis/pruebas Flutter. Esto confirma CI del código integrado; no sustituye pruebas de radio/GATT con hardware.
- La matriz de protocolo está en `docs/AG_BFLS_PUBLIC_PROTOCOL_IMPLEMENTATION.md`; el diagnóstico de navegador está en `docs/WEB_BLUETOOTH_DIAGNOSTICS.md`; el mapa de continuidad está en este handoff y `README.md`.
- No se ha realizado todavía una prueba física AG-BFLS. No afirmar que el descubrimiento BLE, GATT, autenticación o lecturas funcionen en el equipo real hasta ejecutar el procedimiento de la sección 8.
- No se ha escrito EEPROM en un sensor físico. No ejecutar 0x16 ni calibración física sin autorización explícita, respaldo íntegro de los 100 slots y plan de rollback.
- No se ha generado ni publicado APK/AAB; la APK de la app propia se compila fuera de este repositorio. La APK Fuel Master oficial es solo referencia.
- No se realizaron despliegues ni cambios de producción.

### Próximo trabajo permitido

1. Actualizar/clonar `main` y verificar el merge commit anterior.
2. Ejecutar CI local o GitHub Actions si hay cambios posteriores.
3. Realizar primero prueba física de solo lectura: publicidad/SN, GATT FFF0/FFF1/FFF2, lectura 0x1A, autenticación 0x12 con credencial del fabricante no registrada, lecturas 0x0D/0x14 y lectura/backup 0x15.
4. Documentar modelo, firmware, navegador/OS/adaptador y logs saneados.
5. Mantener escritura 0x16 bloqueada operacionalmente hasta autorización, backup verificado y procedimiento de rollback aprobado.
