# Fuel Master Pro — AOOG AG-BFLS

Aplicación Flutter complementaria para calibración de sensores AOOG AG-BFLS, junto al calculador web de geometría de estanques del repositorio.

## Funciones
- Escaneo y conexión BLE a sensores compatibles.
- Autenticación explícita mediante los 8 bytes de credencial entregados por el fabricante. No se prueban PIN universales ni claves derivadas del número de serie.
- Lectura de telemetría, parámetros, coordenadas y bloques de calibración.
- Importación de tablas Excel (`.xlsx`) y CSV/TXT con columnas `Data`, `Level`, `Volume`.
- Conservación de `Data` importado como coordenada de calibración `fixValue`; la importación no fuerza una nueva captura BLE.
- Generación geométrica de tablas que exige captura real de coordenadas 0x1B antes de escribir.
- Escritura de 100 posiciones en diez bloques de diez registros, con respaldo previo y lectura de retorno.
- Restauración de tabla y modo de salida anteriores ante fallos detectados durante la transferencia.

## Desarrollo local
Requisitos: Flutter estable compatible con el SDK declarado en `pubspec.yaml`, Android SDK y dispositivo Android con BLE.

```bash
cd fuel_master_pro
flutter pub get
flutter analyze
flutter test
flutter run
```

La APK se genera desde el entorno de desarrollo del usuario; no se versionan APKs de desarrollo, firmas ni keystores.

## Formato de tabla
Columnas reconocidas por encabezado: `Data` / `Dato` / `Fix`, `Level` / `Nivel`, `Volume` / `Volumen` / `Litros`. Si no existe encabezado, se admite el orden histórico de tres columnas: Data, Level, Volume.

- Data: entero entre 0 y 5000.
- Level: entero entre 0 y 65535 mm.
- Volume: número finito y no negativo en litros.
- Primer registro: origen 0 / 0 / 0 (se agrega si no está presente).
- Data y Level deben crecer estrictamente; Volume no puede disminuir.
- De 2 a 100 registros activos; las posiciones restantes se rellenan como terminadores cero al preparar la escritura BLE.

## Referencia oficial SHVS36
La hoja `calibration` del archivo de referencia contiene 29 registros (incluido el origen), con punto final Data=5000, Level=546 mm y Volume=249.2 L. Sus valores de referencia se reproducen en `test/calibration_table_codec_test.dart`; el archivo original no se incorpora al repositorio.

## Límites de validación
Las pruebas automatizadas y CI no prueban compatibilidad física. Para validar el dispositivo se necesita una unidad AG-BFLS real y una credencial válida del fabricante. Antes de distribuir, verificar conexión, autenticación, lectura/escritura de los diez bloques, comparación byte a byte de los 100 slots, modo litros y rollback. La compatibilidad de ida y vuelta con la app oficial debe probarse por separado.

Ver `../docs/AG_BFLS_CALIBRATION_HANDOFF.md` para el estado de ingeniería y los pasos para continuar.
