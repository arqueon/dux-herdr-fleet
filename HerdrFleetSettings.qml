import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "duxHerdrFleet"

    StyledText {
        width: parent.width
        text: "Dux Herdr Fleet"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Supervisa agentes y spaces de herdr en tu máquina local, máquinas remotas por SSH (`herdr machine list`) y opcionalmente la nueva Herdr Desktop App (`hc` / `herdr-core`). Clic izquierdo abre el panel, clic derecho refresca, clic medio enfoca la ventana de herdr."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "includeRemoteMachines"
        label: "Monitorear máquinas remotas (SSH)"
        description: "Consulta todas las máquinas habilitadas en `herdr machine list` mediante `herdr --machine <host> api snapshot`"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeHerdrCore"
        label: "Incluir Herdr Desktop App (hc)"
        description: "Consulta también `hc ls --json` (`herdr-core`) para mostrar las terminales de la app gráfica de escritorio"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeEmptySpaces"
        label: "Mostrar spaces sin agentes activos"
        description: "Incluye en la lista los workspaces abiertos aunque no tengan un agente corriendo actualmente"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "pillDisplayMode"
        label: "Texto en la barra"
        description: "Qué contador mostrar junto al ícono en la barra"
        options: [
            { label: "Total de agentes (con alerta si hay activos)", value: "total" },
            { label: "Desglose (bloqueados / trabajando / total)", value: "breakdown" },
            { label: "Solo bloqueados + trabajando", value: "activeOnly" },
            { label: "Solo ícono", value: "iconOnly" }
        ]
        defaultValue: "breakdown"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Intervalo de actualización"
        description: "Con qué frecuencia consultar el estado de las máquinas (segundos)"
        defaultValue: 8
        minimum: 3
        maximum: 60
        unit: "seg"
        leftIcon: "schedule"
    }
}
