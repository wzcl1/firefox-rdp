# Firefox over RDP

Lightweight Debian-based container that starts an xrdp server and opens a recent Mozilla Firefox build inside an Openbox session.

## Build and run

```sh
docker compose up --build -d
```

Connect with an RDP client:

- Host: `localhost`
- Port: `3389`
- Username: `browser`
- Password: `change-me`

Change the password before exposing this beyond localhost.

## Configuration

Environment variables:

- `RDP_USER`: Linux/RDP username. Default: `browser`
- `RDP_PASSWORD`: Linux/RDP password. Default: `browser`
- `RDP_UID`: Linux UID for the user. Default: `1000`
- `RDP_GID`: Linux GID for the user. Default: `1000`
- `FIREFOX_START_URL`: URL opened when the RDP session starts. Default: `about:blank`
- `FIREFOX_ARGS`: Extra Firefox CLI arguments, for example `--kiosk`

Example:

```sh
docker run --rm -p 3389:3389 \
  -e RDP_USER=alice \
  -e RDP_PASSWORD='use-a-real-password' \
  -e FIREFOX_START_URL='https://example.com' \
  -e FIREFOX_ARGS='--kiosk' \
  --shm-size=1g \
  firefox-rdp:latest
```

## Notes

- The Dockerfile downloads Firefox from Mozilla at build time using `firefox-latest-ssl`.
- `shm_size: "1gb"` avoids common browser crashes caused by Docker's small default shared memory segment.
- xrdp exposes a password-based login. Put it behind a VPN, SSH tunnel, or trusted private network for real deployments.
