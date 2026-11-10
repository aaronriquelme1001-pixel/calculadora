# 🛢️ Sistema Integral de Calibración de Estanques y Sensores AoooG BLE

Plataforma integral de ingeniería para el cálculo volumétrico de estanques de combustible y calibración directa por Bluetooth Low Energy (BLE) para sensores de varilla **AoooG AG-BFLS / BL Fuel Sensor**.

Incluye:
1. **Web App de Calibración & Modelado:** Motor 2D/3D axonométrico en Canvas, aforo milimétrico, cálculo de capacidad con geometrías complejas y exportación Excel (.xlsx) estricta a 30 filas compatible con la plataforma AoooG.
2. **App Nativa Android (Fuel Master Pro):** Escaneo de sensores BLE, lectura de telemetría (frecuencia Hz, temperatura, batería, RSSI), triangulación física capacitiva inversa y envío directo de la tabla de calibración (Comando `0x16`) y cambio a salida en Litros (Comando `0x19`) sin intermediarios ni computadoras en terreno.

---

## 📐 1. Geometrías de Estanque Soportadas

- **Prisma Rectangular con Múltiples Radios:** 4 radios transversales independientes (piso izq/der, techo izq/der), 4 radios longitudinales (frontal/posterior) y aristas verticales.
- **Cilindro Horizontal & Elíptico / Ovalado:** Integración exacta de cuerda circular y elíptica.
- **Forma D (Volvo / Scania):** Frente redondeado con radios superior e inferior independientes y esquinas dorsales de alivio.
- **Muesca / Escalón (Retroexcavadoras y Maquinaria Pesada):** Configuración de ancho, alto y lado del escalón.
- **Doble Estanque Conectado:** Dimensiones y geometrías independientes para tanque primario y secundario con tubo de interconexión.

---

## ⚡ 2. Protocolo BLE AoooG AG-BFLS

- **Servicio GATT Primario:** `0000FFF0-1212-EFDE-1523-785FEABCD123`
- **Característica de Comando (Write):** `0000FFF1-1212-EFDE-1523-785FEABCD123`
- **Característica de Respuesta (Notify):** `0000FFF2-1212-EFDE-1523-785FEABCD123`

### Estructura de Trama:
```
0C [LL] [ID2 ID1 ID0] [CMD] [DATA...] [CRC8]
```
- **CRC-8:** Polinomio `0x31` (implementación reflexiva `0x8C`, Maxim/Dallas).
- **Comando 0x12:** Autenticación con contraseña de 8 bytes (por defecto `12345678`).
- **Comando 0x0D:** Lectura de frecuencias de fábrica (Vacío y Lleno en Hz).
- **Comando 0x14:** Lectura de telemetría en tiempo real (frecuencia actual, temperatura, batería y salida).
- **Comando 0x16:** Escritura de tabla de calibración en bloques de 10 puntos (80 bytes por bloque: `float32 LE volume`, `uint16 LE level_mm`, `uint16 LE fix_value`).
- **Comando 0x19:** Selección de modo de salida (`0x02` = Litros directos).

---

## 🔬 3. Triangulación de Frecuencia Capacitiva

En las sondas de nivel capacitivas, la capacidad eléctrica $C$ es inversamente proporcional a la frecuencia del oscilador ($f$):
$$C(x) \propto \frac{1}{f(x)}$$

Por tanto, para una fracción de llenado $x \in [0, 1]$:
$$\frac{1}{f(x)} = \frac{1}{f_{\text{vacío}}} + \left(\frac{1}{f_{\text{lleno}}} - \frac{1}{f_{\text{vacío}}}\right) \cdot x$$

La aplicación implementa esta conversión física real para triangular el `fix_value` (0 a 5000 puntos) a partir de los Hz reales del sensor, garantizando exactitud milimétrica incluso ante no linealidades del dieléctrico.

---

## 📱 4. Aplicación Android (Fuel Master Pro)

El código fuente de la app nativa en Flutter se encuentra en el directorio `/fuel_master_pro`:
- **Compilar APK Release:**
  ```bash
  cd fuel_master_pro
  flutter build apk --release
  ```
- **Instalar en dispositivo por ADB:**
  ```bash
  adb install -r build/app/outputs/flutter-apk/app-release.apk
  ```

---

## 💻 5. Web App de Oficina / PC

- Abrir directamente `index.html` en cualquier navegador moderno.
- 100% offline (sin librerías remotas dependientes de internet).
- Generación y descarga de archivos `.xlsx` formateados con las 30 filas exactas requeridas para importación batch en la plataforma AoooG.
