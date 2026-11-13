# AG-BFLS — implementación del protocolo Bluetooth público

Fecha de actualización: 2026-11-13  
Especificación de referencia: AoooG AG-BFLS Developer Protocol, firmware 8.27, publicada 2026-09-19.  
Fuente normativa: https://www.aooog.com/bluetooth-protocol.html

## Transporte GATT

| Rol | UUID |
|---|---|
| Servicio | `0000FFF0-1212-EFDE-1523-785FEABCD123` |
| Escritura FFF1 | `0000FFF1-1212-EFDE-1523-785FEABCD123` |
| Notificaciones FFF2 | `0000FFF2-1212-EFDE-1523-785FEABCD123` |

Habilitar FFF2 antes de enviar comandos. Una solicitud pendiente a la vez. La confirmación de escritura GATT no es confirmación de ejecución: esperar la respuesta FFF2 con el mismo ID y comando.

## Formato de trama

`0C LL ID2 ID1 ID0 CMD DATA... CRC8`

- `LL = 5 + payload.length`; tamaño total = LL + 2.
- ID = uint24 big-endian, identidad comercial/SN; nunca sustituirlo por MAC.
- CRC-8/MAXIM-DOW reflejado: polinomio 0x31 / implementación 0x8C, init 0, xorout 0; cubre LL hasta el último byte de datos, excluye SOF y CRC.
- Estado: payload de un byte, 00 éxito y 01 fallo. En respuestas de lectura, el byte de payload es dato, no un ACK genérico.

## Identificación por publicidad BLE

El parser recibe el payload de fabricante ya separado de los dos bytes Company ID:
- `0xFF43` AOOOG: exactamente 15 bytes. ID/SN uint24 BE en bytes 0–2; modo en nibble alto del byte 3 (00/01/02); battery code en nibble bajo del byte 3 + byte 4; temperatura int16 BE / 8 en bytes 5–6; frecuencia float32 LE en 7–10; salida float32 LE en 11–14.
- `0xFFFF` Universal/Dominator: exactamente 24 bytes; firma `3F 36 B4`, tipo actual `5B`, ID/SN uint24 BE en bytes 6–8, status actual `01` en byte 13, frecuencia/empty/output en los offsets públicos 14,18,20, temperatura byte 22 − 40 y batería byte 23.
- El ID cero, modo AOOOG fuera de 0–2, firma/tipo/status Universal incorrectos, longitudes distintas o mediciones no finitas se rechazan.
- Los bytes reservados no se reinterpretan como otros campos. No derivar SN desde la dirección BLE.

## Comandos públicos implementados

| CMD | Función | Autenticación | Validación |
|---|---|---:|---|
| 01 | Reiniciar | Sí | ACK |
| 02 | Cerrar/hibernar | Sí | ACK; desconexión sola no demuestra éxito |
| 04 / 05 | Escribir / leer intervalo publicidad | 04 sí | Leer 05 de vuelta |
| 0A / 0B | Escribir / leer potencia TX | 0A sí | Valores permitidos -40,-20,-16,-12,-8,-4,0,+3,+4 dBm; leer 0B de vuelta |
| 0C | Continuar tras reinicio | Sí | Leer 0D de vuelta |
| 0D | Leer parámetros (13 bytes) | No | offsets definidos abajo |
| 10 / 11 | Capturar punto vacío / lleno | Sí | ACK y releer 0D/14 |
| 12 | Verificar credencial | No | exactamente 8 bytes; 00 aceptado, 01 rechazado |
| 14 | Leer datos actuales | No | 22 bytes |
| 15 / 16 | Leer / escribir bloque de tabla | 16 sí | 10 registros por bloque; readback byte a byte |
| 19 / 1A | Escribir / leer modo salida | No en firmware público actual | 00 %, 01 mm, 02 L; confirmar con 1A |
| 1B | Leer coordenada de calibración | No | float32 LE, 0–5000 |
| 20 | Leer dirección BLE | No | 6 bytes en orden de pila; invertir para mostrar |
| 21 / 22 | Leer / cambiar formato publicidad | No en firmware público actual | 00 AOOOG, 01 Universal; confirmar con 21 |
| 26 | Leer versión firmware | No | dos bytes decimales major.minor; firmware antiguo puede no responder |

Comandos protegidos centralmente en web y Flutter: 01, 02, 04, 0A, 0C, 10, 11, 16. La autorización se borra al desconectar. No asumir credencial por defecto, ASCII ni derivada del SN.

## Estructuras y conversiones

### 0D — parámetros, 13 bytes

- byte 0: intervalo publicidad, segundos.
- byte 1: reservado.
- byte 2: continuar tras reinicio (00/01).
- byte 3: potencia TX, int8.
- bytes 4–7: frecuencia vacío, float32 LE.
- bytes 8–11: frecuencia lleno, float32 LE.
- byte 12: modo salida 00/01/02.

Frecuencias cero pueden indicar calibración pendiente; no descartar la lectura solo por ser cero.

### 14 — telemetría, 22 bytes

- bytes 0–1: battery code, uint16 BE; porcentaje = floor(clamp((code - 500) × 100 / 220, 0, 100)).
- bytes 2–3: temperatura, int16 BE / 8 °C.
- byte 4: código de versión legacy; no equivale a versión completa.
- byte 5: reservado.
- bytes 6–9: frecuencia lleno, float32 LE.
- bytes 10–13: frecuencia vacío, float32 LE.
- bytes 14–17: frecuencia actual, float32 LE.
- bytes 18–21: salida, float32 LE.
- modo 00: porcentaje = salida / 100.
- modo 01: milímetros; modo 02: litros. No recalcular la salida desde la frecuencia.

### Tabla de calibración 15/16

100 slots; cada entrada ocupa 8 bytes, sin padding:
- float32 LE volumen en litros.
- uint16 LE nivel en mm.
- uint16 LE fix_value, 0–5000, obtenido de 1B.

Leer 10 bloques con índices 0,10,...,90. Respuesta 15 = exactamente 80 bytes y no incluye índice: la app debe conservar el índice solicitado. La respuesta de 15 requiere ATT MTU ≥90.

Escritura 16 = índice + 80 bytes (10 entradas); trama completa 88 bytes y ATT MTU ≥91. Escribir índice 0 borra la tabla anterior completa. Antes de escribir: autenticar, respaldar los 10 bloques y modo original. Después de cada bloque, leer 15 y comparar los 80 bytes. Solo cambiar a modo 1/2 después de verificar toda la tabla. Si falla, restaurar backup y modo anterior y volver a leer. La operación no es atómica: si se interrumpe, no reiniciar ciegamente desde índice 0.

## Diferencias entre Web Bluetooth y Flutter

- Web: el selector abierto `acceptAllDevices` permite elegir periféricos aunque no anuncien manufacturer data. El navegador no entrega de forma consistente SN antes de conectar; si no hay anuncio utilizable, pedir el SN/ID de la etiqueta y confirmarlo mediante lectura 1A. Nunca derivarlo de MAC.
- Web: Web Bluetooth no expone una API estándar para solicitar/consultar el ATT MTU negociado. La app intenta escribir la trama completa de 88 bytes para 16 y maneja el error del stack; no puede garantizar por adelantado que el MTU sea suficiente. La respuesta 15 ocupa 87 bytes y también requiere MTU ≥90. Si el navegador/OS no negocia un MTU suficiente, usar la app Flutter nativa, que solicita 247 y verifica el mínimo.
- Flutter: solicita MTU 247 y valida el mínimo de 90 para leer bloques y 91 para escribirlos. Tras activar notificaciones confirma el ID con lectura 1A. Los escáneres nativos pueden mostrar SN desde manufacturer data; MAC queda solo como dato de transporte/diagnóstico.

## Límites y seguridad

- No guardar ni imprimir credenciales. Nunca incluir claves del fabricante en HTML, repositorio o logs.
- No ejecutar 10/11 ni 16 sin confirmación explícita del técnico; 16 en índice 0 es destructivo para la tabla previa.
- El comando 02 puede cerrar el sensor; se requiere activación con imán para volver a iniciarlo.
- 26 puede no responder en firmware antiguo: mostrar versión no disponible.
- La prueba unitaria/CI no demuestra conexión física. La aceptación final requiere un AG-BFLS real, confirmar SN, lectura 1A, autenticar 12, lectura 14/0D, leer 15 y solo después ensayar escritura con backup aprobado.
