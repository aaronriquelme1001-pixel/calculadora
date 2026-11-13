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
- ID: tres bytes, no un ID de seis caracteres decimal. Para ingreso humano se representan como seis caracteres hexadecimales.
- Manufacturer ID de anuncio conocido: `0xFF43` (AOOOG) y `0xFFFF` (Universal/Dominator), con sus longitudes/firmas específicas.
- Credencial: exactamente ocho bytes del fabricante, sin valores por defecto.
- Comandos usados: `0x0D` parámetros; `0x14` telemetría; `0x15` lectura de bloque; `0x16` escritura de bloque; `0x19/0x1A` establecer/leer modo de salida; `0x12` autenticación.
- Las respuestas deben validarse por ID, comando, longitud y CRC. Los comandos de escritura requieren ACK de éxito.

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
- Se puede aprender el ID de una trama espontánea válida por FFF2 (longitud y CRC comprobados).
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

## 5. Pruebas añadidas

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

## 6. Límites que siguen pendientes

- No hay evidencia de que un AG-BFLS físico haya sido detectado o conectado por esta versión web.
- No se ha validado la conexión GATT real desde el navegador ni el comportamiento de la radio en el equipo del usuario.
- No se ha confirmado que todos los firmwares expongan FFF0/FFF1/FFF2 con estas UUID exactas.
- No se ha demostrado que la escritura web de 81 bytes (índice + 80 bytes) funcione en todos los navegadores y adaptadores.
- No se ha ejecutado todavía el ciclo de escritura/lectura/rollback en un sensor real.
- La compatibilidad con Fuel Master oficial debe probarse con importación/exportación real.
- La aplicación Flutter sigue siendo la ruta prioritaria para la primera prueba física, por su control del MTU.

## 7. Protocolo de prueba física cuando el usuario disponga del sensor

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

## 8. Archivos importantes para continuar

- `app.js`: consola web, protocolo, conexión y operaciones BLE.
- `index.html`: interfaz web y controles de BLE.
- `fuel_master_pro/lib/services/aooog_ble.dart`: UUID, framing, CRC y parseo de anuncios Flutter.
- `fuel_master_pro/lib/services/aooog_manager.dart`: conexión GATT, MTU, autenticación, comandos y memoria.
- `fuel_master_pro/lib/services/calibration_table_codec.dart`: importación/validación de tabla.
- `tests/ble-protocol.test.cjs`: pruebas web del protocolo y del flujo de descubrimiento.
- `docs/WEB_BLUETOOTH_DIAGNOSTICS.md`: diagnóstico navegador BLE.
- `README.md`: mapa general del repositorio.

## 9. APK y archivos de referencia

- No generar nuestra APK/AAB en este repositorio ni en este flujo.
- El repositorio contiene una APK de Fuel Master de referencia añadida por el usuario; no confundirla con un artefacto generado por este proyecto. Verificar derechos/permiso antes de redistribuirla públicamente.
- No borrar ni reescribir historia Git de forma destructiva sin autorización explícita.
