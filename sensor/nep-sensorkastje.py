#!/usr/bin/env python3
"""Fake sensor box: sends one "veld/sensorupload" to the Veldvlucht app, without hardware.

It sends exactly what the real box (sensor/Veldsensor) sends: POST /sensormetingen with
a few made-up measurements, oldest first. Python 3.9+, standard library only.

Examples:
    python3 sensor/nep-sensorkastje.py 172.20.10.1
    python3 sensor/nep-sensorkastje.py 172.20.10.1 --aantal 5 --sensor mijn-veld-s1
    python3 sensor/nep-sensorkastje.py --cloud abcdefghijklmnopqrst --cloud-sleutel sb_publishable_... \
        --sensor-sleutel 0123... --sensor mijn-veld-s1

With --cloud it sends to the central system in Supabase instead, like a box with
CLOUD_PROJECT set (RPC sensor_upload over HTTPS).
"""
import argparse
import json
import random
import sys
import urllib.error
import urllib.request


def make_upload(sensor_id, depth_cm, count, interval_min, with_battery):
    """The same JSON body as the box: one measurement per interval, oldest first."""
    measurements = []
    raw = random.randint(2700, 2800)
    for i in range(count):
        age_s = (count - 1 - i) * interval_min * 60 + 5  # the newest is a few seconds old
        raw = min(4095, raw + random.randint(0, 25))  # soil slowly drying out: raw goes up
        battery = round(3.95 - 0.01 * i, 2) if with_battery else None
        measurements.append({"nr": i + 1, "ageS": age_s, "raw": raw, "batteryVolt": battery})
    return {
        "format": "veld/sensorupload",
        "version": 0,
        "sensorId": sensor_id,
        "depthCm": depth_cm,
        # Like the box after switching on: a random id, and the measurements numbered from 1.
        "boot": random.randint(1, 2**31 - 1),
        "measurements": measurements,
    }


def main():
    parser = argparse.ArgumentParser(description="Stuur nep-sensormetingen naar de Veldvlucht-app.")
    parser.add_argument("host", nargs="?", help="adres van de iPhone, bijvoorbeeld 172.20.10.1 via de hotspot")
    parser.add_argument("--cloud", help="project-ref van Supabase: stuur naar de cloud in plaats van de app")
    parser.add_argument("--cloud-sleutel", help="publishable key van het project (CLOUD_SLEUTEL)")
    parser.add_argument("--sensor-sleutel", help="sleutel van de sensor (SENSOR_SLEUTEL)")
    parser.add_argument("--poort", type=int, default=8787, help="poort van de app (standaard 8787)")
    parser.add_argument("--aantal", type=int, default=5, help="aantal metingen (standaard 5)")
    parser.add_argument("--sensor", default="mijn-veld-s1", help="sensorId (standaard mijn-veld-s1)")
    parser.add_argument("--diepte", type=int, default=15, help="diepte in cm (standaard 15)")
    parser.add_argument("--interval", type=int, default=60, help="minuten tussen de metingen (standaard 60)")
    parser.add_argument("--geen-batterij", action="store_true", help="stuur batteryVolt null, zoals een kastje zonder batterijmeting")
    args = parser.parse_args()
    if args.aantal < 1:
        parser.error("--aantal moet minstens 1 zijn")
    if not args.cloud and not args.host:
        parser.error("geef het adres van de iPhone, of --cloud")
    if args.cloud and not (args.cloud_sleutel and args.sensor_sleutel):
        parser.error("--cloud heeft ook --cloud-sleutel en --sensor-sleutel nodig")

    upload = make_upload(args.sensor, args.diepte, args.aantal, args.interval, not args.geen_batterij)
    headers = {"Content-Type": "application/json"}
    if args.cloud:
        # Exactly what a box with CLOUD_PROJECT sends: the upload with the sensor's key.
        url = "https://{}.supabase.co/rest/v1/rpc/sensor_upload".format(args.cloud)
        body = json.dumps({"p_sleutel": args.sensor_sleutel, "p_upload": upload}).encode("utf-8")
        headers["apikey"] = args.cloud_sleutel
        if args.cloud_sleutel.startswith("eyJ"):
            headers["Authorization"] = "Bearer " + args.cloud_sleutel
    else:
        url = "http://{}:{}/sensormetingen".format(args.host, args.poort)
        body = json.dumps(upload).encode("utf-8")
    print("POST {} ({} metingen, {} bytes)".format(url, args.aantal, len(body)))
    print(json.dumps(upload, indent=2))

    request = urllib.request.Request(url, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            print("Antwoord {}: {}".format(response.status, response.read().decode("utf-8", "replace")))
            return 0 if response.status == 200 else 1  # the box only deletes its measurements on 200
    except urllib.error.HTTPError as error:
        print("Antwoord {}: {}".format(error.code, error.read().decode("utf-8", "replace")))
    except (urllib.error.URLError, OSError) as error:
        print("Geen verbinding: {}".format(getattr(error, "reason", error)))
        print("Is de Veldvlucht-app open, en zit deze computer op hetzelfde netwerk als de iPhone?")
    return 1


if __name__ == "__main__":
    sys.exit(main())
