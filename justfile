# Hangboard Connect IQ app. Run `just` to list recipes.
#
# Every command runs inside `nix-shell -p jdk17 python3`: monkeyc and monkeydo need Java,
# and scripts/check_programs.py needs Python.
# Override with environment variables, e.g.:  DEVELOPER_KEY=~/other_key just build

set shell := ["nix-shell", "-p", "jdk17", "python3", "--run"]

# Defaults
device := env_var_or_default("DEVICE", "fenix7")
key    := env_var_or_default("DEVELOPER_KEY", justfile_directory() + "/developer_key")
sdk    := trim_end_match(`cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"`, "/")

# List recipes
default:
    @just --list --unsorted

# Validate resources/programs/programs.json (see docs/program-format.md)
check:
    python3 scripts/check_programs.py

# Print every step of a program, e.g. `just show "Week 1"`
show name="":
    python3 scripts/check_programs.py --show {{ if name == "" { "" } else { "'" + name + "'" } }}

# Build for one device (default: fenix7)
build dev=device: check
    mkdir -p bin
    '{{sdk}}/bin/monkeyc' -d {{dev}} -f monkey.jungle -o bin/{{dev}}.prg -y '{{key}}' -w

# Build for every device listed in manifest.xml
build-all: check
    mkdir -p bin
    set -e; for d in $(grep -o 'product id="[^"]*"' manifest.xml | cut -d'"' -f2); do echo "== $d"; '{{sdk}}/bin/monkeyc' -d $d -f monkey.jungle -o bin/$d.prg -y '{{key}}' -w; done

# Use bin/crimp.iq for the Connect IQ Store or a private beta (apps.garmin.com/developer).
# Export a release package for all devices: bin/crimp.iq
export: check
    mkdir -p bin
    '{{sdk}}/bin/monkeyc' -e -r -f monkey.jungle -o bin/crimp.iq -y '{{key}}' -w
    @ls -l bin/crimp.iq

# Start the Connect IQ simulator
sim:
    pgrep -qf "ConnectIQ.app" || { env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin open '{{sdk}}/bin/ConnectIQ.app'; for i in $(seq 1 30); do lsof -nP -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 1; done; sleep 10; }

# Build, start the simulator if needed, and run on a device (default: fenix7)
run dev=device: (build dev) sim
    '{{sdk}}/bin/monkeydo' bin/{{dev}}.prg {{dev}}

# List the devices in manifest.xml
devices:
    @grep -o 'product id="[^"]*"' manifest.xml | cut -d'"' -f2

# Remove build output
clean:
    rm -rf bin
