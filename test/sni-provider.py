#!/usr/bin/env python3
import asyncio
import os
import sys

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess, RequestNameReply
from dbus_next.service import ServiceInterface, dbus_property, method

WATCHER_NAME = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
WATCHER_INTERFACE = "org.kde.StatusNotifierWatcher"
ITEM_NAME = "org.omanixy.DeterministicStatusNotifierItem"
PASSIVE_ITEM_NAME = "org.omanixy.PassiveStatusNotifierItem"
ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/Menu"


class Watcher(ServiceInterface):
    def __init__(self):
        super().__init__(WATCHER_INTERFACE)
        self.items = []

    @dbus_property(access=PropertyAccess.READ)
    def RegisteredStatusNotifierItems(self) -> "as":
        return self.items

    @dbus_property(access=PropertyAccess.READ)
    def IsStatusNotifierHostRegistered(self) -> "b":
        return True

    @method()
    def RegisterStatusNotifierItem(self, service: "s") -> None:
        item = service if service.startswith("/") else service + ITEM_PATH
        if item not in self.items:
            self.items.append(item)
            self.emit_properties_changed({"RegisteredStatusNotifierItems": self.items})

    @method()
    def RegisterStatusNotifierHost(self, service: "s") -> None:
        return None


class Item(ServiceInterface):
    def __init__(self, status, marker):
        super().__init__("org.kde.StatusNotifierItem")
        self.status_value = status
        self.marker = marker

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return "ApplicationStatus"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return "omanixy-passive-sni" if self.status_value == "Passive" else "omanixy-deterministic-sni"

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return "Omanixy deterministic SNI"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return self.status_value

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> "u":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return "network-wired"

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionMovie(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return ["", [], self.Title, "deterministic test provider"]

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return MENU_PATH

    @method()
    def Activate(self, x: "i", y: "i") -> None:
        with open(self.marker, "a", encoding="utf-8") as marker:
            marker.write("ACTIVATED\n")
        print("ACTIVATED", flush=True)

    @method()
    def ContextMenu(self, x: "i", y: "i") -> None:
        return None

    @method()
    def SecondaryActivate(self, x: "i", y: "i") -> None:
        return None

    @method()
    def Scroll(self, delta: "i", orientation: "s") -> None:
        return None


class Menu(ServiceInterface):
    def __init__(self, marker):
        super().__init__("com.canonical.dbusmenu")
        self.marker = marker

    @dbus_property(access=PropertyAccess.READ)
    def Version(self) -> "u":
        return 3

    @dbus_property(access=PropertyAccess.READ)
    def TextDirection(self) -> "s":
        return "ltr"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "normal"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "as":
        return []

    @method()
    def GetLayout(self, parent_id: "i", recursion_depth: "i", property_names: "as") -> "u(ia{sv}av)":
        child = Variant("(ia{sv}av)", [1, {"label": Variant("s", "Activate deterministic item")}, []])
        return [1, [0, {}, [child]]]

    @method()
    def AboutToShow(self, item_id: "u") -> "b":
        return True

    @method()
    def Event(self, item_id: "u", event_id: "s", data: "v", timestamp: "a{sv}") -> None:
        if event_id == "clicked":
            with open(self.marker, "a", encoding="utf-8") as marker:
                marker.write("MENU_CLICKED\n")
            print("MENU_CLICKED", flush=True)


async def connect_item(bus, name, status, marker):
    reply = await bus.request_name(name)
    if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
        raise RuntimeError(f"could not own {name}: {reply.name}")
    item = Item(status, marker)
    menu = Menu(marker)
    bus.export(ITEM_PATH, item)
    bus.export(MENU_PATH, menu)

    async def register():
        try:
            introspection = await bus.introspect(WATCHER_NAME, WATCHER_PATH)
            proxy = bus.get_proxy_object(WATCHER_NAME, WATCHER_PATH, introspection)
            watcher = proxy.get_interface(WATCHER_INTERFACE)
            await watcher.call_register_status_notifier_item(name)
        except Exception:
            return

    async def register_forever():
        while True:
            await register()
            await asyncio.sleep(0.25)

    asyncio.create_task(register_forever())
    return item, menu


async def run(mode):
    marker = os.environ.get("SNI_MARKER", "/tmp/omanixy-sni-provider.marker")
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    if mode in ("watcher", "watcher-recovery", "rival-watcher"):
        reply = await bus.request_name(WATCHER_NAME)
        if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
            raise RuntimeError(f"could not own {WATCHER_NAME}: {reply.name}")
        watcher = Watcher()
        bus.export(WATCHER_PATH, watcher)
        await asyncio.Future()
    if mode == "broken-watcher":
        reply = await bus.request_name(WATCHER_NAME)
        if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
            raise RuntimeError(f"could not own {WATCHER_NAME}: {reply.name}")
        await asyncio.Future()
    if mode in ("item", "passive-item"):
        await connect_item(bus, ITEM_NAME if mode == "item" else PASSIVE_ITEM_NAME, "Active" if mode == "item" else "Passive", marker)
        await asyncio.Future()
    raise RuntimeError(f"unknown mode: {mode}")


def main():
    try:
        asyncio.run(run(sys.argv[1]))
    except (BrokenPipeError, asyncio.CancelledError):
        return


if __name__ == "__main__":
    main()
