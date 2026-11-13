# Fuel Master Pro — Calculadora de estanques y calibración AOOOG AG-BFLS

Repositorio único de trabajo: **`main`**. Contiene la calculadora web (HTML/CSS/JavaScript) y la aplicación Android Flutter (`fuel_master_pro/`). La APK se genera fuera de este repositorio, según el flujo de trabajo acordado.

## Componentes

- **Calculadora web:** modelado 2D/3D y cálculo volumétrico de estanques, exportación/importación de tablas y consola BLE experimental.
- **Fuel Master Pro Android:** conexión BLE, telemetría, autenticación explícita, importación de tablas Excel/CSV, lectura de memoria, escritura verificada y restauración ante fallos.
- **Protocolo compartido:** servicio GATT FFF0, escritura FFF1 y notificaciones FFF2.

## Protocolo AOOOG AG-BFLS

Trama:
```
0C [LL] [ID2 ID1 ID0] [CMD] [DATA...] [CRC8]
```

- ID del sensor: tres bytes obtenidos del anuncio BLE AOOOG (manufacturer ID `0xFF43`) o Universal/Dominator (`0xFFFF`). No se inventa ni se fija un ID genérico.
- CRC-8: implementación reflejada con polinomio `0x8C`.
- `0x12`: autenticación con los ocho bytes de credencial entregados por el fabricante. No hay PIN ni clave predeterminada.
- `0x0D`: lectura de parámetros.
- `0x14`: telemetría.
- `0x15`: lectura de un bloque de diez registros.
- `0x16`: escritura de diez registros (80 bytes).
- `0x19` / `0x1A`: escritura y lectura del modo de salida (`0x02` = litros).
- Las respuestas se validan por ID, comando, longitud y CRC. Las operaciones de escritura requieren ACK explícito.

## Tabla de calibración

Formato oficial: `Data | Level | Volume`.

- `Data`: entero de 0 a 5000, conservado como coordenada del sensor (`fixValue`).
- `Level`: entero de 0 a 65535 mm.
- `Volume`: litros, finito y no negativo.
- Entre 2 y 100 registros activos, con origen `0 / 0 / 0`.
- Data y Level estrictamente crecientes; Volume no decreciente.
- Los slots restantes hasta 100 se rellenan con terminadores cero.
- La importación de Excel/CSV valida encabezados, filas y rangos; no convierte silenciosamente datos inválidos a cero.
- Las coordenadas Data importadas se preservan al exportar y transferir.
- Las tablas generadas por geometría no se escriben al sensor como si sus coordenadas fueran mediciones reales. La consola web exige una tabla importada con Data real.

La tabla de referencia SHVS36 contiene 29 registros incluyendo origen y termina en Data=5000, Level=546 mm y Volume=249.2 L. El Excel del cliente no se versiona.

## Consola BLE web

La búsqueda web usa `requestDevice({ acceptAllDevices: true })`: el selector del navegador muestra dispositivos BLE cercanos sin depender del nombre anunciado, del UUID de servicio en el anuncio ni de los manufacturer data. El usuario selecciona el dispositivo; el software no puede iniciar un escaneo silencioso ni enumerar dispositivos fuera del selector del navegador.

Después de seleccionar, se conecta a GATT y consulta el servicio FFF0, característica FFF1 (escritura) y FFF2 (notificaciones). `watchAdvertisements()` se usa solo como fuente opcional para extraer el ID AOOOG/Universal; su ausencia no impide descubrir ni conectar GATT. También se acepta una trama espontánea válida recibida por FFF2. Si ninguna fuente entrega el ID, se solicita el ID real de seis caracteres hexadecimales de la etiqueta/documentación. No hay valor de ejemplo predeterminado. Antes de habilitar operaciones, se valida el ID mediante la lectura de solo lectura 0x1A y se exige un modo válido (0, 1 o 2). Un ID incorrecto provoca desconexión; no se ejecutan escrituras.

Si el selector no muestra dispositivos, revisar primero navegador compatible, HTTPS, radio/adaptador BLE, permisos del sistema operativo, sensor encendido y anunciando, y que la aplicación oficial no mantenga ocupada la conexión. Ver `docs/WEB_BLUETOOTH_DIAGNOSTICS.md` para el procedimiento completo de diagnóstico.

La escritura de tabla requiere autenticación, respaldo de los diez bloques, ACK por bloque, lectura de retorno byte a byte y verificación del modo de salida. Ante un fallo intenta restaurar tabla y modo originales. La API Web Bluetooth no expone una lectura fiable del MTU negociado; si el navegador/dispositivo no acepta el paquete de bloque, la operación falla y activa la ruta de restauración. Para la validación BLE física completa se recomienda la app Flutter.

El modo DEMO no se presenta como conexión ni escritura física. La altura de sonda modificada desde el formulario web se aplica únicamente al modelo de cálculo local; no cambia parámetros del sensor.

## Desarrollo y validación

Web:
```bash
node --check app.js
node --test tests/*.test.cjs
```

Android:
```bash
cd fuel_master_pro
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

GitHub Actions ejecuta validación JavaScript y análisis/pruebas Flutter en `main`.

## Seguridad y publicación

- No versionar credenciales, PIN, claves, keystores, APK firmadas ni archivos privados de clientes.
- GitHub Pages publica exclusivamente `index.html`, `app.js` y `app.css` desde un directorio de distribución temporal. No publica el repositorio completo ni planillas internas.
- No incluir datos sensibles en logs ni documentación.

## Validación física pendiente

Los tests automáticos no prueban compatibilidad con hardware real. Antes de distribuir o afirmar interoperabilidad con Fuel Master oficial se debe probar en un AG-BFLS de banco:

1. Autenticación con credencial real, sin registrarla.
2. Lectura de los diez bloques y respaldo de los 100 slots.
3. Importación de la tabla SHVS36 de 29 filas.
4. Escritura y lectura de retorno byte a byte de los 100 slots.
5. Verificación del modo litros y telemetría.
6. Prueba de rollback controlada.
7. Prueba de ida y vuelta con la aplicación oficial.

Registrar modelo, firmware, MTU cuando esté disponible, fecha y logs saneados. No declarar compatibilidad física hasta completar estas pruebas.
