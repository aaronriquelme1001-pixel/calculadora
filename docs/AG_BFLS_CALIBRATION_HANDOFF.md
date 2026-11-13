# AG-BFLS — handoff técnico consolidado en main

Actualizado: 2026-11-13

## Repositorio y flujo de trabajo
- Repositorio: `aaronriquelme1001-pixel/calculadora`.
- Rama única de trabajo: `main`.
- La reparación Flutter previamente mantenida en PR #4 fue fusionada en main mediante merge commit `44b33ffc3b24694e08347eaad1278a925acdfe01`.
- No abrir nuevas ramas para el trabajo ordinario de este proyecto. No generar APK aquí; el usuario la genera en su entorno separado.

## Alcance implementado
- Flutter: codec de Excel/CSV con columnas Data/Level/Volume, preservación de Data como fixValue, validación de rangos y monotonicidad.
- Flutter: autenticación explícita con 8 bytes del fabricante, ID BLE de 3 bytes, validación de tramas, lectura/escritura de bloques, respaldo, lectura de retorno y restauración best-effort.
- Web: framing BLE alineado al protocolo Flutter (ID de 3 bytes, CRC, longitud), ID obtenido de anuncio AOOOG/Universal, cola de comando con timeout y validación de respuesta.
- Web: lectura real de 10 bloques; escritura exige autenticación, backup, ACK por bloque, lectura de retorno byte a byte y verificación del modo 0x02.
- Web: importación XLSX/CSV/TXT con columnas reconocidas, validación de cada fila y preservación de coordenadas Data en exportación.
- Web: DEMO separado de operaciones físicas. Altura configurada desde la interfaz solo cambia el modelo local.
- Pages: publica únicamente index.html, app.js y app.css; no usa el repositorio completo como artefacto.

## Referencia de calibración
Libro de referencia: `CALIBRACION SHVS36 782-415.xlsx`, hoja `calibration`, encabezados `Data | Level | Volume`.
- 29 registros incluyendo origen 0/0/0.
- Último punto: Data=5000, Level=546 mm, Volume=249.2 L.
- El archivo original no se versiona; las filas de referencia se conservan en pruebas Flutter.

## Reglas de protocolo y seguridad
- Trama: `0C [LL] [ID2 ID1 ID0] [CMD] [DATA...] [CRC8]`.
- ID real derivado del anuncio: company ID 0xFF43 (AOOOG) o 0xFFFF (Universal/Dominator).
- Credencial: exactamente 8 bytes provistos por el fabricante. No usar valores por defecto ni registrar credenciales.
- Toda respuesta se valida por ID, comando, longitud y CRC.
- Comandos de escritura requieren ACK 0x00.
- Web Bluetooth no expone un MTU negociado fiable. La consola web intenta la escritura larga con respuesta GATT y aborta/ejecuta rollback si falla.
- Flutter exige MTU >= 91 antes de escribir.
- Tabla de 100 slots: diez bloques de diez registros, 8 bytes por registro. Se respaldan y verifican todos los bloques; modo de salida se verifica por lectura 0x1A.

## Última validación automatizada conocida
- Commit de código Flutter `582a3665a79fb0c462d681e5648563e746dc457a`.
- GitHub Actions run: https://github.com/aaronriquelme1001-pixel/calculadora/actions/runs/43442576737
- JavaScript syntax: PASS.
- Flutter pub get: PASS.
- Flutter analyze con avisos no fatales: PASS (se reportaron 36 avisos/info heredados).
- Flutter tests: PASS, 21 pruebas.
- La implementación web BLE nueva aún debe pasar la ejecución CI posterior a estos commits.

## Validación física obligatoria antes de distribución
1. Conectar un AG-BFLS real y capturar anuncio BLE/ID.
2. Autenticar con credencial del fabricante.
3. Leer los diez bloques y conservar los 100 slots originales.
4. Importar la tabla oficial SHVS36.
5. Escribir los diez bloques y comparar los 100 slots byte a byte.
6. Verificar modo 0x02 y telemetría.
7. Ejecutar rollback controlado.
8. Comparar importación/exportación con Fuel Master oficial.

Las pruebas de software no sustituyen esta validación. No declarar compatibilidad física ni distribuir como verificado hasta completar el banco de pruebas.
