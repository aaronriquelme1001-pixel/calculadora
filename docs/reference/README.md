# Documentación y Archivos Oficiales de Referencia AoooG / AG-BFLS

Este directorio contiene los archivos oficiales de referencia provistos por el fabricante **AoooG** para el sensor capacitivo de nivel de combustible **AG-BFLS**:

---

## Contenido

1. **`AG-BFLS_User_Manual.pdf`**
   * Manual oficial de usuario e instalación.
   * Procedimiento de corte y ajuste de altura de la sonda.
   * Procedimiento de calibración de puntos cero:
     * **Punto Vacío (`0x10`):** Sonda seca al aire libre o estanque vacío (frecuencia típica ~15.000 Hz).
     * **Punto Lleno (`0x11`):** Sonda 100% sumergida en diésel/combustible (frecuencia típica ~10.000 Hz).
   * Modo de salida de telemetría y tabla de linealización.

2. **`AG-BFLS_Datasheet.pdf`**
   * Ficha técnica y hoja de especificaciones del sensor.
   * Rango de medición (0 - 5.000 puntos raw AoooG).
   * Parámetros eléctricos, comunicación BLE 4.0 / RS485 / analógica, consumo y tolerancias.

3. **`Fuel Master V0.1.4.apk` y `Fuel Master V0.1.4.apk.zip`**
   * APK oficial de Android de **Fuel Master V0.1.4**.
   * Utilizada como referencia de ingeniería inversa y compatibilidad para la estructura de tramas (`0x0C [LL] [ID2 ID1 ID0] [CMD] ... [CRC8]`), autenticación de 8 bytes (`0x12`), bloques de calibración de 100 puntos (`0x16`/`0x15`) y modo litros (`0x19 0x02`).
