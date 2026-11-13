# Diagnóstico Web Bluetooth — AOOOG AG-BFLS

Actualizado: 2026-11-13. Fuente de verdad: `main`.

## Modo de búsqueda disponible

Las dos acciones visibles de búsqueda utilizan el selector nativo abierto de Web Bluetooth:

```js
navigator.bluetooth.requestDevice({
  acceptAllDevices: true,
  optionalServices: [AoooGProtocol.SERVICE_UUID]
});
```

No se aplica filtro por nombre, UUID anunciado ni `manufacturerData`. Esto es intencional: ciertos AG-BFLS pueden no exponer los datos de fabricante antes del emparejamiento. El selector puede mostrar periféricos ajenos; el usuario debe elegir el sensor correcto y la aplicación valida después su identidad a nivel de protocolo. Los datos AoooG `0xFF43` y Universal `0xFFFF` siguen siendo fuentes opcionales de identificación cuando el navegador los entrega.

## Identificación por Número de Serie (SN) vs Dirección MAC

En la app oficial Fuel Master y en las etiquetas de los sensores físicos, el dispositivo se identifica mediante su **Número de Serie (SN)**, un entero decimal de 24 bits:
- **Cálculo exacto oficial:** `SN = (byte0 << 16) | (byte1 << 8) | byte2` (ej. bytes `[0x0C, 0x52, 0x02]` corresponden a `SN: 807426`).
- **Visualización en la interfaz:** La cabecera muestra prioritariamente **`AG-BFLS • SN: [número]`**, acompañado de su representación hexadecimal, nivel de batería (%) y frecuencia (Hz). No se presenta la dirección MAC como identidad primaria.
- **Ingreso y edición manual:** El diálogo admite indistintamente el SN decimal de la etiqueta (ej. `807426`) o el ID de 3 bytes en hexadecimal (ej. `0C:52:02` o `78:24:15`), verificándolo inmediatamente mediante lectura segura 0x1A antes de cualquier operación.

## Flujo de conexión

1. Comprobar HTTPS o localhost y disponibilidad de `navigator.bluetooth.requestDevice`.
2. Abrir selector nativo con `acceptAllDevices: true`.
3. El usuario selecciona el periférico.
4. Conectar a GATT y descubrir servicio `FFF0-1212-EFDE-1523-785FEABCD123`.
5. Resolver características FFF1 (write) y FFF2 (notify), activar notificaciones.
6. Intentar leer el ID de manufacturer data con `watchAdvertisements()` si el navegador lo soporta. Esta función es opcional y nunca condiciona la aparición del periférico ni la conexión GATT.
7. Si llega una trama espontánea por FFF2, solo se aprende el ID desde una telemetría `0x14` de exactamente 22 bytes, con ID no nulo, CRC válido y campos numéricos finitos/coherentes. Una trama de otro comando, incompleta o con valores inválidos no puede establecer identidad.
8. Si no se obtuvo ID, solicitar al técnico el ID real impreso/documentado para ese sensor. No se ofrece ID por defecto ni se deduce desde el nombre Bluetooth.
9. Validar el ID mediante el comando de solo lectura 0x1A. Solo se considera identificado si la respuesta tiene el ID/comando/CRC correctos y devuelve un modo 0, 1 o 2.
10. Ante ID no confirmado, cancelar y desconectar. No se habilita autenticación, lectura de memoria ni escritura.

## Requisitos del navegador y del sistema

- Usar Google Chrome o Microsoft Edge actualizado basado en Chromium.
- La página debe servirse por HTTPS. `http://localhost` también es contexto seguro para desarrollo.
- Bluetooth debe estar habilitado en el equipo y el adaptador debe soportar Bluetooth Low Energy (BLE).
- En Windows, comprobar que el adaptador y su controlador BLE estén activos en Administrador de dispositivos y que Windows no tenga Bluetooth deshabilitado.
- En Android, usar Chrome actualizado, activar Bluetooth y conceder los permisos del sistema que Android solicite para dispositivos cercanos/Bluetooth.
- Safari/iOS y Firefox no son plataformas de validación para esta consola Web Bluetooth.
- Cerrar o desconectar Fuel Master oficial y cualquier otra app que esté usando el mismo sensor antes de probar. Algunos firmwares/adaptadores no aceptan conexiones simultáneas.
- Mantener el sensor encendido, dentro de alcance y en un estado en que esté anunciando y acepte conexiones.

## Si el selector no muestra ningún dispositivo

1. Confirmar que se abrió el selector del navegador y no se canceló.
2. Probar Chrome o Edge actualizado en un equipo con adaptador BLE conocido.
3. Abrir la misma página por HTTPS.
4. Confirmar que el sensor aparece en un escáner BLE independiente del sistema o en la app oficial. Si tampoco aparece allí, investigar alimentación, modo de anuncio, alcance, firmware y radio del sensor.
5. Desconectar Fuel Master del sensor y repetir.
6. Reiniciar Bluetooth del equipo y el sensor; repetir con el equipo a menos de un metro.
7. En Chrome de escritorio se puede revisar `chrome://bluetooth-internals/#devices` como diagnóstico del stack Bluetooth. No reemplaza el selector Web Bluetooth ni demuestra compatibilidad GATT.
8. Si el selector muestra el sensor pero GATT falla, el problema ya no es descubrimiento: revisar que anuncie el servicio FFF0 y que exponga FFF1/FFF2 con las propiedades esperadas.

## Diagnóstico específico: "Connection Error: Connection attempt failed"

Este es el error exacto que arroja Chromium en Windows cuando el usuario ve el sensor en el selector, hace clic en "Emparejar", pero `device.gatt.connect()` falla al establecer el enlace de radio:

1. **Causa #1 (95% en pruebas de campo): El sensor ya está conectado a otro equipo**
   - Los sensores AoooG AG-BFLS utilizan microcontroladores BLE (ej. nRF51822 / nRF52832) configurados en modo **Single-Link**. Solo pueden mantener **una conexión central activa**.
   - Si la app Fuel Master está abierta en un teléfono Android/iOS, o si el Bluetooth del teléfono se conectó automáticamente en segundo plano al sensor, el sensor rechaza inmediatamente cualquier nueva conexión desde Windows.
   - **Solución:** Apagar el Bluetooth del teléfono celular o cerrar por completo Fuel Master antes de pulsar "Buscar Sensor" en la PC.

2. **Causa #2: Latencia de negociación GATT en Windows 10/11**
   - El stack WinRT de Windows a veces agota el tiempo si el sensor tiene un intervalo de anuncio prolongado o entra en modo de bajo consumo.
   - **Solución implementada:** La aplicación ahora reintenta automáticamente la conexión GATT hasta 3 veces con una pausa de 800 ms antes de desistir.

3. **Causa #3: Servicio FFF0 en formato 128-bit vs alias 16-bit**
   - Aunque el protocolo oficial documenta el UUID `0000FFF0-1212-EFDE-1523-785FEABCD123`, algunos firmwares exponen el servicio bajo el alias estándar `0xFFF0`.
   - **Solución implementada:** El código ahora resuelve primero el UUID de 128 bits y, si el dispositivo no lo expone bajo ese formato, resuelve automáticamente el servicio primario `0xFFF0` y sus características `0xFFF1` y `0xFFF2`.

4. **Causa #4: Periférico emparejado o cacheado en Windows**
   - Si Windows guardó el sensor previamente en `Configuración de Windows > Bluetooth y dispositivos`, el sistema operativo puede intentar una autenticación cifrada en lugar de GATT directo.
   - **Solución:** Quitar el dispositivo en la configuración de Windows y reiniciar el Bluetooth del adaptador de la PC.

## Qué significa cada resultado

- **No aparece en selector:** radio/OS/navegador/periférico no está visible o no anuncia. El código ahora no lo excluye por nombre o manufacturer ID.
- **Aparece y el usuario lo selecciona, pero falla GATT:** revisar servicio UUID, conexión ocupada, firmware y permisos.
- **GATT conecta pero no se obtiene ID:** el navegador puede no exponer anuncios; comprobar ID real de etiqueta y confirmar mediante lectura 0x1A.
- **ID no confirmado:** no es seguro operar. No intentar escritura ni adivinar IDs.
- **ID confirmado pero autenticación falla:** revisar credencial oficial de 8 bytes y compatibilidad del firmware.
- **Lectura funciona pero escritura falla:** detenerse, conservar respaldo y revisar MTU/longitud de paquete/ACK/rollback. No repetir escrituras a ciegas.

## Límites conocidos

- Web Bluetooth no ofrece un escaneo BLE continuo y silencioso. `requestDevice` abre el selector controlado por el navegador.
- `watchAdvertisements()` tiene soporte desigual y permisos específicos; solo se usa como fuente adicional del ID.
- La API Web Bluetooth no entrega un MTU negociado fiable para dimensionar de forma preventiva el bloque de 81 bytes de escritura (índice + 80 bytes). La ruta web puede fallar por límites del navegador/OS. La aplicación Flutter sigue siendo la ruta prioritaria para las pruebas físicas de lectura/escritura.
- No se ha confirmado hardware real en este cambio. La validación automatizada prueba protocolo y reglas de selección, no la radio ni el sensor físico.

## Regresión de identificación y autenticación

Las pruebas automatizadas cubren conversión SN/ID, anuncios, CRC, descubrimiento abierto, validación estricta de telemetría y conversión de credencial de 16 hex a ocho bytes. También comprueban que la interfaz no aprenda identidad desde una trama arbitraria y que la autenticación dependa del ACK positivo `0x12`.

Ejecutar:

```bash
node --check app.js
node --test tests/*.test.cjs
```

Estas pruebas ejercitan las funciones puras y guardas de código; no simulan el stack BLE del sistema operativo ni sustituyen una prueba de conexión física con AG-BFLS.

## Próxima prueba física necesaria

Registrar sin credenciales: navegador y versión, sistema operativo, modelo del adaptador BLE, nombre visible del sensor en selector, si aparece en escáner BLE externo, si GATT FFF0 se descubre, si FFF1/FFF2 existen, resultado de lectura 0x1A, modelo/firmware del sensor y logs saneados. Nunca registrar la credencial ni compartirla en GitHub.
