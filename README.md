# Bazooka

Ubuntu Security Workstation Manager

Bazooka is a single-file Bash tool for provisioning Ubuntu security workstations for cybersecurity learning, CTF preparation, bug bounty preparation, local security labs, defensive research, workstation maintenance, workspace organization, and report template generation.

AUTHORIZED USE ONLY.

## Project Identity

| Field | Value |
| --- | --- |
| Project | Bazooka |
| Maintainer | `voxynoxy` |
| Repository | `voxynoxy/bazooka-workstation` |
| URL | <https://github.com/voxynoxy/bazooka-workstation> |

Use Bazooka only on systems you own, local labs, CTF environments, learning environments, or targets where you have explicit authorization. Bazooka is not intended for unauthorized access, credential theft, phishing, malware, persistence, evasion, ransomware, botnets, or attack automation against public targets.

## Project Status

Bazooka currently ships as one executable file:

```text
bazookasetup.sh
```

The script includes Bash strict mode, CLI flags, an interactive menu, state files, log files, dry-run mode, healthcheck, repair helpers, Docker local labs, workspace generation, report template generation, metadata backup/restore, and system command installation.

## Supported OS

Primary targets:

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Newer compatible Ubuntu releases

The script exits cleanly on non-Ubuntu systems or unsupported Ubuntu versions.

## Requirements

Minimum:

- Ubuntu 22.04/24.04
- Bash 4+
- `sudo`
- internet access for package installation
- a sudo-capable user for commands that modify the system

Optional:

- Docker, for local labs

## Quick Start

This section is for users who only want to install and use Bazooka.

Clone the repository:

```bash
git clone git@github.com:voxynoxy/bazooka-workstation.git
cd bazooka-workstation
```

Make the script executable:

```bash
chmod +x bazookasetup.sh
```

Show help:

```bash
./bazookasetup.sh --help
```

Install the system command:

```bash
sudo ./bazookasetup.sh --install-system
```

After installation, run:

```bash
bazookasetup --status
```

Or open the interactive menu:

```bash
bazookasetup
```

If you only want to test Bazooka without installing the system command, run it directly from the cloned repository:

```bash
./bazookasetup.sh --help
./bazookasetup.sh --no-color --dry-run --minimal
./bazookasetup.sh
```

## Full Installation From Scratch

1. Clone the repository:

```bash
git clone git@github.com:voxynoxy/bazooka-workstation.git
cd bazooka-workstation
```

2. Make the script executable:

```bash
chmod +x bazookasetup.sh
```

3. Check dry-run mode:

```bash
./bazookasetup.sh --no-color --dry-run --minimal
```

4. Install the system command:

```bash
sudo ./bazookasetup.sh --install-system
```

5. Show status:

```bash
bazookasetup --status
```

6. Run healthcheck:

```bash
bazookasetup --healthcheck
echo $?
```

Note: exit code `4` means healthcheck completed with `UNHEALTHY` status. It is not a crash; it is a signal that the workstation needs attention or is not ready yet.

## Interactive Menu

Run:

```bash
./bazookasetup.sh
```

Or, after system installation:

```bash
bazookasetup
```

The interactive menu provides:

- Minimal Profile
- Recon Profile
- Web Profile
- Full Deployment
- Docker Engine
- Local Labs
- Wordlists
- Status Dashboard
- Health Check
- Repair Environment
- Backup State
- Restore State
- Benchmark
- Create Workspace
- Report Template
- Update Bazooka
- Uninstall

## Global Flags

| Flag | Purpose |
| --- | --- |
| `--help` | Show help output |
| `--version` | Show version, maintainer, and repository |
| `--dry-run` | Show planned changes without applying them |
| `--no-color` | Disable ANSI color output |
| `--verbose` | Enable additional debug output |
| `--quiet` | Suppress non-essential output |
| `--yes` | Assume yes for supported confirmation prompts |
| `--install-system` | Install command to `/usr/local/bin/bazookasetup` |

## Commands

| Command | Requires sudo | Dry-run | Description |
| --- | --- | --- | --- |
| `--minimal` | Yes | Yes | Install core packages and base tooling |
| `--recon` | Yes | Yes | Install authorized reconnaissance utilities |
| `--web` | Yes | Yes | Install web security testing environment |
| `--docker` | Yes | Yes | Install Docker Engine and Compose plugin |
| `--labs` | Yes | Yes | Deploy local-only Docker labs |
| `--wordlists` | Yes | Yes | Create wordlist structure and symlink system wordlists |
| `--all` | Yes | Yes | Run minimal, recon, web, docker, labs, and wordlists |
| `--status` | No | N/A | Show workstation status |
| `--healthcheck` | No | N/A | Validate workstation readiness |
| `--repair` | Yes | Yes | Run safe apt/dpkg/state repair steps |
| `--backup` | Yes | Yes | Back up Bazooka metadata state |
| `--restore` | Yes | Yes | Restore Bazooka metadata state |
| `--benchmark` | No | N/A | Run a lightweight local benchmark |
| `--workspace NAME` | No | Yes | Create project workspace structure |
| `--report-template` | No | Yes | Generate a Markdown report template |
| `--update` | No | Yes | Check configured release source |
| `--uninstall` | Yes | Yes | Remove Bazooka system command and managed state |

## Recommended First Run

For a new user, start with:

```bash
./bazookasetup.sh --no-color --dry-run --minimal
sudo ./bazookasetup.sh --minimal
./bazookasetup.sh --healthcheck
```

To install Docker:

```bash
sudo ./bazookasetup.sh --docker
```

If the user is added to the `docker` group, log out and log back in before using Docker without sudo.

To deploy local labs:

```bash
sudo ./bazookasetup.sh --labs
```

Local labs bind only to localhost:

- OWASP Juice Shop: `127.0.0.1:3000`
- DVWA: `127.0.0.1:8080`
- WebGoat: `127.0.0.1:8081`

Do not expose these labs to public networks.

## Profiles

### Minimal Profile

Core packages and base tooling:

- curl
- wget
- git
- ca-certificates
- gnupg
- lsb-release
- software-properties-common
- build-essential
- unzip
- jq
- tree
- tmux
- vim
- nano
- python3
- python3-pip
- python3-venv

Command:

```bash
sudo ./bazookasetup.sh --minimal
```

### Recon Profile

Authorized reconnaissance utilities:

- whois
- dnsutils
- traceroute
- netcat-openbsd
- nmap
- httpie
- sslscan
- optional apt-available tools such as massdns, whatweb, and testssl.sh

Command:

```bash
sudo ./bazookasetup.sh --recon
```

Some packages are checked with `apt-cache policy` because availability can differ between Ubuntu releases and configured repositories.

### Web Profile

Web security testing environment:

- nikto
- sqlmap
- wfuzz
- ffuf
- gobuster
- feroxbuster
- zaproxy

Command:

```bash
sudo ./bazookasetup.sh --web
```

Use these tools only for authorized testing.

## Docker Engine

Install Docker Engine from Docker's official repository:

```bash
sudo ./bazookasetup.sh --docker
```

Actions performed:

- add Docker's official GPG key
- add Docker's apt source
- install `docker-ce`, `docker-ce-cli`, `containerd.io`, and `docker-compose-plugin`
- enable and start the Docker service
- offer to add the current user to the `docker` group

Security note: users in the `docker` group have root-equivalent control over the Docker daemon.

## Local Labs

Deploy local-only training labs:

```bash
sudo ./bazookasetup.sh --labs
```

All bind addresses must remain localhost:

```text
127.0.0.1
```

Stop labs:

```bash
docker compose -f /var/lib/bazooka/labs/docker-compose.yml down
```

## Wordlists

Create this structure:

```text
~/bazooka/wordlists/
├── common/
├── web/
├── dns/
├── content-discovery/
└── custom/
```

Command:

```bash
sudo ./bazookasetup.sh --wordlists
```

Bazooka does not download leaked data or credential dumps. It only creates directories and symlinks official/system wordlists that already exist on the workstation.

## Workspace

Create a project workspace:

```bash
./bazookasetup.sh --workspace project-name
```

Structure:

```text
~/bazooka/workspaces/project-name/
├── notes/
├── screenshots/
├── findings/
├── reports/
├── evidence/
├── references/
├── scope/
└── archive/
```

Project names must not contain:

- path traversal such as `../`
- slash `/`
- backslash
- characters other than letters, numbers, dot, underscore, and hyphen

## Report Template

Generate a Markdown report:

```bash
./bazookasetup.sh --report-template
```

Output directory:

```text
~/bazooka/reports/
```

Template sections:

- Executive Summary
- Scope
- Rules of Engagement
- Methodology
- Findings Summary
- Detailed Findings
- Risk Rating
- Evidence
- Recommendations
- Appendix

## State, Logs, and Data

Bazooka uses these paths:

| Path | Purpose |
| --- | --- |
| `/var/lib/bazooka/` | State directory |
| `/var/log/bazooka.log` | Log file |
| `~/bazooka/workspaces/` | Project workspaces |
| `~/bazooka/reports/` | Report templates |
| `~/bazooka/wordlists/` | Wordlist structure |
| `~/.bazooka/backups/` | Metadata backups |

Backups include only Bazooka metadata. They do not include sensitive workspace findings or evidence.

## Healthcheck

Run:

```bash
./bazookasetup.sh --healthcheck
echo $?
```

Healthcheck verifies:

- internet connectivity
- DNS resolution
- Ubuntu version
- APT state
- disk space
- memory
- dpkg state
- required commands
- Docker status
- Docker group access
- Bazooka state directory
- Bazooka log file

Overall status:

- `HEALTHY`
- `DEGRADED`
- `UNHEALTHY`

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Success, including successful dry-run operations |
| `1` | General runtime error |
| `2` | Usage error, invalid argument, or unsupported OS |
| `3` | Privilege error |
| `4` | Healthcheck completed with `UNHEALTHY` status |
| `5` | Resource not found, such as restore with no backups |
| `130` | Interrupted by user |

## Backup and Restore

Back up metadata:

```bash
sudo ./bazookasetup.sh --backup
```

Restore metadata:

```bash
sudo ./bazookasetup.sh --restore
```

Restore does not reinstall packages automatically. If restored metadata references a profile that is not installed on the current system, Bazooka prints a manual recommendation.

## Repair

Run safe repair steps:

```bash
sudo ./bazookasetup.sh --repair
```

Actions performed:

- `apt update`
- `dpkg --configure -a`
- `apt --fix-broken install -y`
- `apt autoremove -y`
- ensure the state directory and log file exist

Run dry-run first:

```bash
sudo ./bazookasetup.sh --dry-run --repair
```

## Uninstall

Remove Bazooka-managed state:

```bash
sudo ./bazookasetup.sh --uninstall
```

Removed by default:

- `/usr/local/bin/bazookasetup`
- `/var/lib/bazooka`

Not removed automatically:

- Docker
- installed apt packages
- workspaces and reports, unless the user gives an additional explicit confirmation

## Troubleshooting

### Permission denied when running the script

Run:

```bash
chmod +x bazookasetup.sh
./bazookasetup.sh --help
```

### System install rejected because the file is not executable

Run:

```bash
chmod +x bazookasetup.sh
sudo ./bazookasetup.sh --install-system
```

### Command requires sudo

If this appears:

```text
requires root privileges. Re-run with sudo.
```

Run the command again with `sudo`.

### Healthcheck exits with code 4

Exit code `4` means healthcheck found `UNHEALTHY` status.

Show details:

```bash
./bazookasetup.sh --healthcheck
```

Then try:

```bash
sudo ./bazookasetup.sh --repair
```

### Docker group is not active yet

After `--docker`, log out and log back in, or open a new session.

Check:

```bash
groups
docker ps
```

## Pre-Release Test Checklist

Before public release, test in clean Ubuntu 22.04 and 24.04 VMs:

```bash
bash -n bazookasetup.sh
./bazookasetup.sh --no-color --help
./bazookasetup.sh --no-color --dry-run --all
sudo ./bazookasetup.sh --minimal
sudo ./bazookasetup.sh --recon
sudo ./bazookasetup.sh --web
sudo ./bazookasetup.sh --docker
sudo ./bazookasetup.sh --labs
sudo ./bazookasetup.sh --wordlists
./bazookasetup.sh --healthcheck
sudo ./bazookasetup.sh --backup
sudo ./bazookasetup.sh --restore
./bazookasetup.sh --benchmark
./bazookasetup.sh --workspace test-project
./bazookasetup.sh --report-template
sudo ./bazookasetup.sh --uninstall
```

For packages unavailable in the default repository, Bazooka prints `WARN` and skips optional packages where possible. Always validate in clean VMs because package availability can differ between Ubuntu releases.

## Security Scope

Bazooka supports:

- workstation setup
- local-only lab deployment
- authorized CTF/bug bounty preparation
- defensive research environment
- report template generation
- workspace organization
- safe maintenance helpers

Bazooka does not implement:

- malware
- credential theft
- phishing
- persistence
- evasion
- ransomware
- botnets
- exploit automation
- public-target attack workflows

## Maintainer Notes

This project is already fairly complex for a single Bash file. If the feature set keeps growing, consider:

- splitting the script into shell modules
- adding test scripts
- adding CI with `bash -n`, `shellcheck`, and dry-run smoke tests
- moving the main engine to Python or Go if the logic grows significantly

## Support

[![Star this repo](https://img.shields.io/github/stars/voxynoxy/bazooka-workstation?style=flat-square&label=Star&cacheSeconds=3600)](https://github.com/voxynoxy/bazooka-workstation)

If Bazooka saved you setup time, a star on the repository is always appreciated.

Solana support is welcome, but never expected.

![Solana](https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white) 
```text
2XEFJrnzoMRssr65HwgTdnckonkS4kdmQsJWUYzLGC9b`
```
