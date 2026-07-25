# Retro Waveform Control Plane

This optional Compose profile runs the Retro Waveform FastAPI control plane behind Caddy. It
does not receive USB devices, PipeWire or ALSA sockets, host networking, or privileged access.
The container therefore starts safely with SDR and DAC components degraded.

## Build and Start

Run these commands on the server after cloning the `retro-waveform` repository:

```bash
cd ~/retro-waveform
make image

cd /srv/compose
sudo docker compose --profile retro-waveform up -d retro-waveform
```

Add a LAN DNS record for `retro-waveform` pointing to the server IP, then browse:

```text
http://retro-waveform
```

The IP fallback is `http://<server-ip>/retro-waveform`.

## Validation

```bash
cd /srv/compose
sudo docker compose --profile retro-waveform ps retro-waveform
sudo docker compose --profile retro-waveform logs --tail 100 retro-waveform
curl -fsS -H 'Host: retro-waveform' http://127.0.0.1/api/v1/health/ready
```

Expected: the container is healthy and returns `{"status":"healthy"}`. SDR, DAC, and real
Spotify playback remain unavailable until a separately tested host-native audio agent exists.

## Updates and Rollback

Build the new image from a checked-out Retro Waveform revision, then recreate only this service:

```bash
cd ~/retro-waveform
make image

cd /srv/compose
sudo docker compose --profile retro-waveform up -d --force-recreate retro-waveform
```

To stop it without affecting the rest of the stack:

```bash
cd /srv/compose
sudo docker compose --profile retro-waveform stop retro-waveform
```
