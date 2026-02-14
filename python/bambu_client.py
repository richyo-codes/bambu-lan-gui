#!/usr/bin/env python3
"""Minimal Bambu MQTT/FTPS client for light control and print submission."""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
from dataclasses import dataclass
from ftplib import FTP_TLS
from threading import Event
from typing import Any

import paho.mqtt.client as mqtt


def _strip_slash(path: str) -> str:
    return path[1:] if path.startswith("/") else path


def _int_list(value: str) -> list[int]:
    if not value.strip():
        return []
    return [int(item.strip()) for item in value.split(",")]


@dataclass
class ClientConfig:
    host: str
    device_id: str
    username: str
    access_code: str
    mqtt_port: int
    ftps_port: int
    insecure_tls: bool

    @property
    def request_topic(self) -> str:
        return f"device/{self.device_id}/request"

    @property
    def report_topic(self) -> str:
        return f"device/{self.device_id}/report"


class BambuClient:
    def __init__(self, cfg: ClientConfig):
        self.cfg = cfg
        self._sequence = int(time.time() * 1000)

    def next_sequence(self) -> str:
        self._sequence += 1
        return str(self._sequence)

    def publish(self, payload: dict[str, Any], timeout_sec: float = 8.0) -> None:
        connected = Event()

        def on_connect(client: mqtt.Client, _userdata: Any, _flags: Any, reason_code: int, _properties: Any = None) -> None:
            if reason_code == 0:
                connected.set()

        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        client.on_connect = on_connect
        client.username_pw_set(self.cfg.username, self.cfg.access_code)
        client.tls_set(cert_reqs=ssl.CERT_NONE if self.cfg.insecure_tls else ssl.CERT_REQUIRED)
        client.tls_insecure_set(self.cfg.insecure_tls)

        client.connect(self.cfg.host, self.cfg.mqtt_port, keepalive=30)
        client.loop_start()
        try:
            if not connected.wait(timeout=timeout_sec):
                raise RuntimeError("MQTT connect timeout")
            info = client.publish(self.cfg.request_topic, json.dumps(payload, separators=(",", ":")), qos=0)
            info.wait_for_publish(timeout=timeout_sec)
            if not info.is_published():
                raise RuntimeError("MQTT publish timeout")
        finally:
            client.loop_stop()
            client.disconnect()

    def upload_file(self, local_path: str, remote_name: str | None = None, timeout_sec: float = 20.0) -> str:
        target_name = remote_name or os.path.basename(local_path)
        ftps = FTP_TLS()
        ftps.connect(self.cfg.host, self.cfg.ftps_port, timeout=timeout_sec)
        try:
            ftps.login(self.cfg.username, self.cfg.access_code)
            ftps.prot_p()
            with open(local_path, "rb") as handle:
                ftps.storbinary(f"STOR {target_name}", handle)
            return target_name
        finally:
            try:
                ftps.quit()
            except Exception:
                ftps.close()

    def command_light(self, mode: str) -> dict[str, Any]:
        return {
            "system": {
                "sequence_id": self.next_sequence(),
                "command": "ledctrl",
                "led_node": "chamber_light",
                "led_mode": mode,
                "led_on_time": 500,
                "led_off_time": 500,
                "loop_times": 1,
                "interval_time": 1000,
            }
        }

    def command_gcode_file(self, filename: str) -> dict[str, Any]:
        clean_name = _strip_slash(filename)
        return {
            "print": {
                "sequence_id": self.next_sequence(),
                "command": "gcode_file",
                "param": f"/sdcard/{clean_name}",
            }
        }

    def command_project_file(
        self,
        filename: str,
        plate_id: int,
        use_ams: bool,
        timelapse: bool,
        bed_levelling: bool,
        flow_cali: bool,
        vibration_cali: bool,
        ams_mapping: list[int],
    ) -> dict[str, Any]:
        clean_name = _strip_slash(filename)
        task_name, _, _ext = clean_name.rpartition(".")
        if not task_name:
            task_name = clean_name
        return {
            "print": {
                "sequence_id": self.next_sequence(),
                "command": "project_file",
                "param": f"Metadata/plate_{plate_id}.gcode",
                "project_id": "0",
                "profile_id": "0",
                "task_id": "0",
                "subtask_id": "0",
                "subtask_name": task_name,
                "file": "",
                "url": f"file:///sdcard/{clean_name}",
                "md5": "",
                "timelapse": timelapse,
                "bed_type": "auto",
                "bed_levelling": bed_levelling,
                "flow_cali": flow_cali,
                "vibration_cali": vibration_cali,
                "layer_inspect": True,
                "ams_mapping": ams_mapping,
                "use_ams": use_ams,
            }
        }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bambu printer protocol client (MQTT + FTPS).")
    parser.add_argument("--host", required=True, help="Printer IP or cloud MQTT host.")
    parser.add_argument("--device-id", required=True, help="Printer serial/device id for topic path.")
    parser.add_argument("--username", default="bblp", help="MQTT/FTPS username (default: bblp).")
    parser.add_argument("--access-code", required=True, help="Printer access code (used as password).")
    parser.add_argument("--mqtt-port", type=int, default=8883, help="MQTT TLS port (default: 8883).")
    parser.add_argument("--ftps-port", type=int, default=990, help="FTPS port (default: 990).")
    parser.add_argument(
        "--insecure-tls",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Disable TLS certificate verification (default: true).",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print payload but do not send.")

    sub = parser.add_subparsers(dest="command", required=True)

    light = sub.add_parser("light", help="Toggle chamber light.")
    light.add_argument("mode", choices=["on", "off"])

    gcode = sub.add_parser("gcode-file", help="Print an existing .gcode file from SD card.")
    gcode.add_argument("--filename", required=True, help="SD file path or name.")

    project = sub.add_parser("project-file", help="Print a plate from existing .3mf on SD card.")
    project.add_argument("--filename", required=True, help="3mf file path/name on SD card.")
    project.add_argument("--plate-id", type=int, default=1)
    project.add_argument("--ams-mapping", default="", help="Comma-separated tray mapping, e.g. 0,1,2")
    project.add_argument("--use-ams", action=argparse.BooleanOptionalAction, default=None)
    project.add_argument("--timelapse", action=argparse.BooleanOptionalAction, default=True)
    project.add_argument("--bed-levelling", action=argparse.BooleanOptionalAction, default=True)
    project.add_argument("--flow-cali", action=argparse.BooleanOptionalAction, default=True)
    project.add_argument("--vibration-cali", action=argparse.BooleanOptionalAction, default=True)

    upload_print = sub.add_parser("project-upload-print", help="Upload local .3mf via FTPS, then print.")
    upload_print.add_argument("--local-file", required=True, help="Local path to .3mf file.")
    upload_print.add_argument("--remote-name", default=None, help="Optional target filename on SD card.")
    upload_print.add_argument("--plate-id", type=int, default=1)
    upload_print.add_argument("--ams-mapping", default="", help="Comma-separated tray mapping, e.g. 0,1,2")
    upload_print.add_argument("--use-ams", action=argparse.BooleanOptionalAction, default=None)
    upload_print.add_argument("--timelapse", action=argparse.BooleanOptionalAction, default=True)
    upload_print.add_argument("--bed-levelling", action=argparse.BooleanOptionalAction, default=True)
    upload_print.add_argument("--flow-cali", action=argparse.BooleanOptionalAction, default=True)
    upload_print.add_argument("--vibration-cali", action=argparse.BooleanOptionalAction, default=True)

    return parser


def resolve_use_ams(explicit_use_ams: bool | None, mapping: list[int]) -> bool:
    if explicit_use_ams is not None:
        return explicit_use_ams
    return 254 not in mapping if mapping else True


def main() -> int:
    args = build_parser().parse_args()
    cfg = ClientConfig(
        host=args.host,
        device_id=args.device_id,
        username=args.username,
        access_code=args.access_code,
        mqtt_port=args.mqtt_port,
        ftps_port=args.ftps_port,
        insecure_tls=args.insecure_tls,
    )
    client = BambuClient(cfg)

    payload: dict[str, Any] | None = None
    if args.command == "light":
        payload = client.command_light(args.mode)

    elif args.command == "gcode-file":
        payload = client.command_gcode_file(args.filename)

    elif args.command == "project-file":
        mapping = _int_list(args.ams_mapping)
        payload = client.command_project_file(
            filename=args.filename,
            plate_id=args.plate_id,
            use_ams=resolve_use_ams(args.use_ams, mapping),
            timelapse=args.timelapse,
            bed_levelling=args.bed_levelling,
            flow_cali=args.flow_cali,
            vibration_cali=args.vibration_cali,
            ams_mapping=mapping,
        )

    elif args.command == "project-upload-print":
        remote_name = args.remote_name
        if not args.dry_run:
            remote_name = client.upload_file(args.local_file, remote_name=args.remote_name)
            print(f"Uploaded to SD as: {remote_name}")
        else:
            remote_name = remote_name or os.path.basename(args.local_file)
            print(f"DRY RUN: would upload {args.local_file} -> {remote_name}")
        mapping = _int_list(args.ams_mapping)
        payload = client.command_project_file(
            filename=remote_name,
            plate_id=args.plate_id,
            use_ams=resolve_use_ams(args.use_ams, mapping),
            timelapse=args.timelapse,
            bed_levelling=args.bed_levelling,
            flow_cali=args.flow_cali,
            vibration_cali=args.vibration_cali,
            ams_mapping=mapping,
        )

    if payload is None:
        raise RuntimeError("No payload generated")

    print(json.dumps(payload, indent=2))
    if args.dry_run:
        print("DRY RUN: payload not published")
        return 0

    client.publish(payload)
    print(f"Published to {cfg.request_topic}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
