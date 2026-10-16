# Network Sentinel 🛡️

**Network Sentinel** es una solución ligera de monitoreo y visualización del estado de red diseñada para entornos Windows. Permite supervisar interfaces, métricas clave de conectividad y parámetros de seguridad a través de un widget de escritorio HTML interactivo, ejecutado de fondo mediante scripts automatizados y PowerShell.

---

## 🚀 Características principales

- **Monitoreo en tiempo real:** Supervisión de adaptadores de red, estado de la conexión y métricas de tráfico.
- **Widget de escritorio dinámico:** Interfaz visual compacta basada en HTML/CSS/JS (`network_sentinel desktop_widget.html`) para visualizar el estado del sistema sin saturar la pantalla.
- **Ejecución modular:** Arquitectura dividida en módulos PowerShell (`src/`) para control de widgets, recopilación de métricas y gestión de procesos.
- **Lanzador silencioso:** Integración con ejecutables y scripts auxiliares (`.bat`, `.vbs`, `.exe`) para inicio sin ventanas intrusivas de consola.
- **Configuración flexible:** Ajustes personalizables mediante el archivo `network_sentinel_settings.json`.

---

## 📁 Estructura del proyecto

```text
Network Sentinel/
├── src/                          # Módulos y scripts de soporte en PowerShell
│   ├── _combine.ps1              # Script de compilación/ensamblado de componentes
│   ├── _widget_ctl.ps1           # Controlador del ciclo de vida del widget
│   └── ...                       # Módulos de recopilación de métricas
├── network_sentinel desktop_widget.html  # Interfaz gráfica del widget
├── network_sentinel_settings.json       # Archivo de configuración local
├── NetworkSentinel.bat           # Lanzador por lotes
├── NetworkSentinel.ps1           # Script principal de PowerShell
├── NetworkSentinel.vbs           # Lanzador silencioso (sin ventana de consola)
├── NetworkSentinel.exe           # Binario ejecutable principal
├── NetworkSentinel.ico           # Icono de la aplicación
└── LEEME.txt                     # Instrucciones básicas de uso