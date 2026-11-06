import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "duxHerdrFleet"

    StyledText {
        width: parent.width
        text: I18n.trFor("duxHerdrFleet", "Dux Herdr Fleet")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("duxHerdrFleet", "Monitors herdr agents and workspaces across your local machine, remote SSH machines (`herdr machine list`), and optionally the Herdr Desktop App (`hc` / `herdr-core`). Left-click opens the popout, right-click refreshes, middle-click focuses the herdr window.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "includeRemoteMachines"
        label: I18n.trFor("duxHerdrFleet", "Monitor remote machines (SSH)")
        description: I18n.trFor("duxHerdrFleet", "Queries all enabled machines in `herdr machine list` via `herdr --machine <host> api snapshot`")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeHerdrCore"
        label: I18n.trFor("duxHerdrFleet", "Include Herdr Desktop App (hc)")
        description: I18n.trFor("duxHerdrFleet", "Queries `herdr-app ls`, `herdr-core` state, and `hc ls --json` across local and remote `hc` machines")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "includeEmptySpaces"
        label: I18n.trFor("duxHerdrFleet", "Show spaces without active agents")
        description: I18n.trFor("duxHerdrFleet", "Includes open workspaces in the tree even when they have no running agent")
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "endpointSwitchMode"
        label: I18n.trFor("duxHerdrFleet", "Cross-machine switching")
        description: I18n.trFor("duxHerdrFleet", "herdr has no API to change the machine its window shows, so switching drives herdr's Go to picker. Kitty remote control (needs listen_on in kitty.conf) sends keys only to the herdr window and checks its screen before Enter. The virtual-keyboard options type into the focused window through a Wayland virtual keyboard and are opt-in. Off only focuses the pane on its server and notifies you.")
        options: [
            { label: I18n.trFor("duxHerdrFleet", "Kitty remote control (recommended)"), value: "kitty" },
            { label: I18n.trFor("duxHerdrFleet", "Kitty, else Wayland virtual keyboard"), value: "auto" },
            { label: I18n.trFor("duxHerdrFleet", "Wayland virtual keyboard only"), value: "keyboard" },
            { label: I18n.trFor("duxHerdrFleet", "Off (focus on server + notification)"), value: "off" }
        ]
        defaultValue: "kitty"
    }

    ToggleSetting {
        settingKey: "interceptNotifications"
        label: I18n.trFor("duxHerdrFleet", "Clickable herdr notifications")
        description: I18n.trFor("duxHerdrFleet", "Replaces herdr notifications with copies that jump to the originating pane when clicked")
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "pillDisplayMode"
        label: I18n.trFor("duxHerdrFleet", "Bar pill label")
        description: I18n.trFor("duxHerdrFleet", "What counter to display next to the bar icon")
        options: [
            { label: I18n.trFor("duxHerdrFleet", "Total agents (highlighted when active)"), value: "total" },
            { label: I18n.trFor("duxHerdrFleet", "Breakdown (blocked / working / total)"), value: "breakdown" },
            { label: I18n.trFor("duxHerdrFleet", "Blocked + working only"), value: "activeOnly" },
            { label: I18n.trFor("duxHerdrFleet", "Icon only"), value: "iconOnly" }
        ]
        defaultValue: "breakdown"
    }

    SliderSetting {
        settingKey: "remoteRefreshInterval"
        label: I18n.trFor("duxHerdrFleet", "Background remote refresh")
        description: I18n.trFor("duxHerdrFleet", "How often remote SSH machines are polled while the popout is closed, so the bar notices blocked agents elsewhere (0 = only while the popout is open)")
        defaultValue: 60
        minimum: 0
        maximum: 600
        unit: I18n.trFor("duxHerdrFleet", "sec")
        leftIcon: "cloud_sync"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: I18n.trFor("duxHerdrFleet", "Refresh interval")
        description: I18n.trFor("duxHerdrFleet", "How often to poll machine snapshots (seconds)")
        defaultValue: 15
        minimum: 10
        maximum: 120
        unit: I18n.trFor("duxHerdrFleet", "sec")
        leftIcon: "schedule"
    }
}
