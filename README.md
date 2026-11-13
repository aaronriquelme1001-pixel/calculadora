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

- ID del sensor y Número de Serie (SN):
  - Protocolo binario: 3 bytes `[ID2 ID1 ID0]`.
  - Número de Serie comercial: entero decimal de 24 bits impreso en la etiqueta y mostrado en Fuel Master: $\text{SN} = (\text{byte}_0 \ll 16) \mid (\text{byte}_1 \ll 8) \mid \text{byte}_2$ (ej. `[0x0C, 0x52, 0x02]` $\to$ `SN: 807426`).
  - Anuncios reconocidos: manufacturer data `0xFF43` (AoooG, 15 bytes) y `0xFFFF` (Universal, 24 bytes), extrayendo ID, SN, nivel de batería, temperatura y frecuencia.
- CRC-8: implementación reflejada con polinomio `0x8C`.
- Comandos soportados:
  - `0x01` / `0x02`: reinicio e hibernación del sensor.
  - `0x0D`: lectura de parámetros (frecuencia vacío y lleno).
  - `0x10` / `0x11`: fijar punto vacío (0%) y punto lleno (100%).
  - `0x12`: autenticación con credencial de 8 bytes (16 caracteres hexadecimales).
  - `0x14`: telemetría periódica en vivo.
  - `0x15` / `0x16`: lectura y escritura de bloques de calibración (10 filas / 80 bytes).
  - `0x19` / `0x1A`: escritura y lectura del modo de salida (`0x02` = litros directos).

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

## Consola BLE web (Diseño Blanco Sobrio y Compacto)

La consola web BLE (`#panelBleSensor`) utiliza el mismo sistema de diseño blanco sobrio que el resto de la aplicación (`background: #ffffff`, borde sutil `1px solid #e2e8f0`). Se eliminaron todos los recuadros oscuros y cajas anidadas, organizando los controles en:
1. **Cabecera compacta:** Nombre, badges de estado (`EN VIVO`, `BLOQUEADO`), Número de Serie decimal (`SN: [número]`), HEX, porcentaje de batería y botones de acción.
2. **Barra de telemetría horizontal (KPI Ribbon):** Franja limpia en gris suave (`#f8fafc`) con Nivel (mm), Volumen (L), Frecuencia (Hz) y Batería/Temp (°C) en una sola fila.
3. **Área de control en dos columnas directas:**
   - Columna 1: Puntos Cero (Vacío y Lleno) con botones fijar (0x10/0x11), más altura local y delta Hz.
   - Columna 2: Subida y lectura de 100 posiciones (0x15/0x16), selector de modo litros (0x19), credencial de 16 hex y acciones de energía (0x01/0x02).

### Búsqueda e identificación Bluetooth

- Tanto **Buscar Sensor** como **Todos** abren el selector sin filtros mediante `acceptAllDevices: true`. Es deliberado: algunos AG-BFLS no exponen `manufacturerData` antes de la conexión, por lo que un filtro AoooG/Universal puede ocultarlos.
- El identificador primario de la aplicación es el **Número de Serie (SN)** de la etiqueta, convertido al ID binario de tres bytes del protocolo. La dirección MAC nunca se interpreta como SN.
- El ID puede obtenerse del anuncio AoooG/Universal si el navegador lo expone, o de una trama espontánea de telemetría `0x14` completa y coherente. Una trama arbitraria con CRC válido no puede fijar la identidad.
- Si el navegador no entrega el ID, se solicita el SN/ID de la etiqueta. Antes de habilitar operaciones se confirma con lectura segura `0x1A`; si no coincide o la respuesta es inválida, se desconecta.
- La credencial se valida como 16 caracteres hexadecimales y se convierte a ocho bytes únicamente al autenticar. No se almacena ni se registra.

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

## Archivos de referencia oficiales del fabricante AoooG

El repositorio incluye en `docs/reference/` los tres documentos y aplicaciones originales del fabricante para asegurar compatibilidad estricta con el hardware real:
- `docs/reference/AG-BFLS_User_Manual.pdf` (1.5 MB): Manual de usuario oficial, instalación mecánica, cableado y calibración física (puntos vacío y lleno).
- `docs/reference/AG-BFLS_Datasheet.pdf` (733 KB): Ficha técnica, precisión capacitiva, protocolo, señales y especificaciones eléctricas.
- `docs/reference/Fuel Master V0.1.4.apk` (57.6 MB): APK oficial de referencia del fabricante.
- `docs/reference/README.md`: Resumen y hashes de integridad de los archivos de referencia.

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
