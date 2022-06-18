#!/bin/bash

# This file is part of nvitop, the interactive NVIDIA-GPU process viewer.
# License: GNU GPL version 3.

# shellcheck disable=SC2016,SC2312

set -e
shopt -s inherit_errexit
set -u

function abort() {
	echo "$@" >&2
	exit 1
}

# shellcheck disable=2292
if [ -z "${BASH_VERSION:-}" ]; then
	abort "Bash is required to interpret this script."
fi

# shellcheck disable=1091
if [[ "$(uname -s)" != "Linux" ]]; then
	abort "This script only supports Ubuntu Linux."
elif (source /etc/os-release && [[ "${NAME:-}" != "Ubuntu" ]]); then
	abort "This script only supports Ubuntu Linux."
fi

# String formatters
if [[ -t 1 ]]; then
	tty_escape() { printf "\033[%sm" "$1"; }
else
	tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_green="$(tty_mkbold 32)"
tty_yellow="$(tty_mkbold 33)"
tty_white="$(tty_mkbold 37)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

function usage() {
	cat <<EOS
Usage: bash $(basename "$0") [--package=PKG] [--upgrade-only] [--latest] [--dry-run] [--yes] [--help]

Options:
  --package PKG    Install the specified driver package. (e.g. ${tty_bold}nvidia-driver-470${tty_reset})
  --upgrade-only   Keep the installed NVIDIA driver package and only upgrade the package version.
  --latest         Upgrade to the latest NVIDIA driver, the old driver package may be removed.
  --dry-run, -n    List all available NVIDIA driver packages and exit.
  --yes, -y        Do not ask for confirmation.
  --help, -h       Show this help and exit.

Examples:

    bash $(basename "$0")
    bash $(basename "$0") --package=nvidia-driver-470
    bash $(basename "$0") --upgrade-only
    bash $(basename "$0") --latest

${tty_yellow}NOTE:${tty_reset} During the install process, the script will offload the NVIDIA kernel modules. Please terminate the
processes that are using the NVIDIA GPUs, e.g., \`watch nvidia-smi\`, \`nvitop\`, and the GNOME Display Manager.
The script will install the latest NVIDIA driver if no NVIDIA driver is installed in the system.
EOS
}

REQUESTED_DRIVER=''
UPGRADE_ONLY=''
LATEST=''
DRY_RUN=''
YES=''
unset HAVE_SUDO_ACCESS
while [[ "$#" -gt 0 ]]; do
	arg="$1"
	shift
	case "${arg}" in
		--package)
			REQUESTED_DRIVER="$1"
			shift
			;;
		--package=*)
			REQUESTED_DRIVER="${arg#*=}"
			;;
		--upgrade-only)
			if [[ -n "${LATEST}" ]]; then
				abort 'Both option `--upgrade-only` and `--latest` are set.'
			fi
			UPGRADE_ONLY=1
			;;
		--latest)
			if [[ -n "${UPGRADE_ONLY}" ]]; then
				abort 'Both option `--upgrade-only` and `--latest` are set.'
			fi
			LATEST=1
			;;
		--dry-run | -n)
			DRY_RUN=1
			HAVE_SUDO_ACCESS=1
			;;
		--yes | -y)
			YES=1
			;;
		--help | -h)
			usage
			exit
			;;
		*)
			usage >&2
			echo >&2
			abort "Invalid option '${arg}'"
			;;
	esac
done

function apt-list-packages() {
	dpkg-query --show --showformat='${Installed-Size} ${binary:Package} ${Version} ${Status}\n' |
		grep -v deinstall | sort -n | awk '{ print $1" "$2" "$3 }'
}

function apt-list-nvidia-packages() {
	local packages
	packages="$(
		apt-list-packages |
			awk '$2 ~ /nvidia.*-([0-9]+)(:.*)?$/ { print $2 }' |
			sort
	)"
	echo "${packages//$'\n'/ }"
}

function apt-installed-version() {
	apt-cache policy "$1" | grep -F 'Installed' | awk '{ print $2 }'
}

function apt-candidate-version() {
	apt-cache policy "$1" | grep -F 'Candidate' | awk '{ print $2 }'
}

function exec_cmd() {
	printf "%s" "$@" | awk \
		'BEGIN {
			RESET = "\033[0m";
			BOLD = "\033[1m";
			UNDERLINE = "\033[4m";
			UNDERLINEOFF = "\033[24m";
			RED = "\033[31m";
			GREEN = "\033[32m";
			YELLOW = "\033[33m";
			WHITE = "\033[37m";
			GRAY = "\033[90m";
			IDENTIFIER = "[_a-zA-Z][_a-zA-Z0-9]*";
			idx = 0;
			in_string = 0;
			double_quoted = 1;
			printf("%s$", BOLD WHITE);
		}
		{
			for (i = 1; i <= NF; ++i) {
				style = WHITE;
				post_style = WHITE;
				if (!in_string) {
					if ($i ~ /^-/)
						style = YELLOW;
					else if ($i == "sudo" && idx == 0) {
						style = UNDERLINE GREEN;
						post_style = UNDERLINEOFF WHITE;
					}
					else if ($i ~ "^" IDENTIFIER "=" && idx == 0) {
						style = GRAY;
						'"if (\$i ~ \"^\" IDENTIFIER \"=[\\\"']\") {"'
							in_string = 1;
							double_quoted = ($i ~ "^" IDENTIFIER "=\"");
						}
					}
					else if ($i ~ /^[12&]?>>?/ || $i == "\\")
						style = RED;
					else {
						++idx;
						'"if (\$i ~ /^[\"']/) {"'
							in_string = 1;
							double_quoted = ($i ~ /^"/);
						}
						if (idx == 1)
							style = GREEN;
					}
				}
				if (in_string) {
					if (style == WHITE)
						style = "";
					post_style = "";
					'"if ((double_quoted && \$i ~ /\";?\$/ && \$i !~ /\\\\\";?\$/) || (!double_quoted && \$i ~ /';?\$/))"'
						in_string = 0;
				}
				if (($i ~ /;$/ && $i !~ /\\;$/) || $i == "|" || $i == "||" || $i == "&&") {
					if (!in_string) {
						idx = 0;
						if ($i !~ /;$/)
							style = RED;
					}
				}
				if ($i ~ /;$/ && $i !~ /\\;$/)
					printf(" %s%s%s;%s", style, substr($i, 1, length($i) - 1), (in_string ? WHITE : RED), post_style);
				else
					printf(" %s%s%s", style, $i, post_style);
				if ($i == "\\")
					printf("\n\t");
			}
		}
		END {
			printf("%s\n", RESET);
		}' >&2
	# shellcheck disable=SC2294
	eval "$@"
}

shell_join() {
	local arg
	printf "%s" "$1"
	shift
	for arg in "$@"; do
		printf " "
		printf "%s" "${arg// /\ }"
	done
}

chomp() {
	printf "%s" "${1/"$'\n'"/}"
}

ohai() {
	printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
	printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

ring_bell() {
	# Use the shell's audible bell.
	if [[ -t 1 ]]; then
		printf "\a"
	fi
}

getc() {
	local save_state
	save_state="$(/bin/stty -g)"
	/bin/stty raw -echo
	IFS='' read -r -n 1 -d '' "$@"
	/bin/stty "${save_state}"
}

CONFIRM_MESSAGE="Press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
wait_for_user() {
	local c
	echo
	echo "${CONFIRM_MESSAGE}"
	getc c
	# we test for \r and \n because some stuff does \r instead
	if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]; then
		exit 1
	fi
}

function have_sudo_access() {
	if [[ "${EUID:-"${UID}"}" == "0" ]]; then
		return 0
	fi

	if [[ ! -x "/usr/bin/sudo" ]]; then
		return 1
	fi

	local -a SUDO=("/usr/bin/sudo")
	if [[ -n "${SUDO_ASKPASS-}" ]]; then
		SUDO+=("-A")
	fi

	if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
		ohai "Checking sudo access (press ${tty_yellow}Ctrl+C${tty_white} to list the driver versions only)." >&2
		exec_cmd "${SUDO[*]} -v && ${SUDO[*]} -l mkdir &>/dev/null"
		HAVE_SUDO_ACCESS="$?"
	fi

	return "${HAVE_SUDO_ACCESS}"
}

# shellcheck disable=SC2310
if have_sudo_access; then
	exec_cmd 'sudo apt-get update'
	if ! (apt-cache policy | grep -qF 'graphics-drivers/ppa/ubuntu'); then
		exec_cmd 'sudo apt-get install software-properties-common apt-transport-https --yes'
		exec_cmd 'sudo add-apt-repository ppa:graphics-drivers/ppa --yes'
		exec_cmd 'sudo apt-get update'
	fi
	echo
fi

# shellcheck disable=SC2207
AVAILABLE_DRIVERS=($(
	apt-cache search --names-only nvidia-driver |
		awk '$1 ~ /^nvidia-driver-([0-9]+)$/ { print $1 }' |
		sort -V
))

if [[ "${#AVAILABLE_DRIVERS[@]}" -eq 0 ]]; then
	abort "No available drivers found from APT."
fi

LATEST_DRIVER="${AVAILABLE_DRIVERS[-1]}"
LATEST_DRIVER_VERSION="$(apt-candidate-version "${LATEST_DRIVER}")"

INSTALLED_DRIVER="$(apt-list-packages | awk '$2 ~ /nvidia-driver-([0-9]+)$/ { print $2 }')"
if [[ -n "${INSTALLED_DRIVER}" ]]; then
	INSTALLED_DRIVER_VERSION="$(apt-installed-version "${INSTALLED_DRIVER}")"
	INSTALLED_DRIVER_CANDIDATE_VERSION="$(apt-candidate-version "${INSTALLED_DRIVER}")"
else
	INSTALLED_DRIVER_VERSION=''
	INSTALLED_DRIVER_CANDIDATE_VERSION=''
fi

ohai "Available NVIDIA drivers:"
for driver in "${AVAILABLE_DRIVERS[@]}"; do
	if [[ "${driver}" == "${INSTALLED_DRIVER}" ]]; then
		if [[ "${INSTALLED_DRIVER_VERSION}" == "${INSTALLED_DRIVER_CANDIDATE_VERSION}" ]]; then
			if [[ "${driver}" == "${LATEST_DRIVER}" ]]; then
				echo "${tty_green}${driver} [${INSTALLED_DRIVER_VERSION}]${tty_reset} ${tty_yellow}[installed]${tty_reset} (up-to-date)"
			else
				echo "${tty_bold}${driver} [${INSTALLED_DRIVER_VERSION}]${tty_reset} ${tty_yellow}[installed]${tty_reset} (up-to-date)"
			fi
		else
			echo "${tty_bold}${driver} [${INSTALLED_DRIVER_VERSION}]${tty_reset} ${tty_yellow}[installed]${tty_reset} (upgradable to [${INSTALLED_DRIVER_CANDIDATE_VERSION}])"
		fi
	elif [[ "${driver}" == "${LATEST_DRIVER}" ]]; then
		echo "${tty_bold}${tty_green}${driver} [${LATEST_DRIVER_VERSION}]${tty_reset} (latest)"
	else
		echo "${driver} [$(apt-candidate-version "${driver}")]"
	fi
done
echo

if [[ -z "${REQUESTED_DRIVER}" ]]; then
	if [[ -n "${LATEST}" || -z "${INSTALLED_DRIVER}" ]]; then
		REQUESTED_DRIVER="${LATEST_DRIVER}"
		REQUESTED_DRIVER_VERSION="${LATEST_DRIVER_VERSION}"
	else
		REQUESTED_DRIVER="${INSTALLED_DRIVER}"
		REQUESTED_DRIVER_VERSION="${INSTALLED_DRIVER_CANDIDATE_VERSION}"
	fi
else
	REQUESTED_DRIVER_VERSION="$(apt-candidate-version "${REQUESTED_DRIVER}")"
	if [[ -z "${REQUESTED_DRIVER_VERSION}" ]]; then
		abort "Unable to locate package ${REQUESTED_DRIVER}."
	fi
fi

if [[ "${INSTALLED_DRIVER}" == "${REQUESTED_DRIVER}" && "${INSTALLED_DRIVER_VERSION}" == "${REQUESTED_DRIVER_VERSION}" ]]; then
	ohai "Your NVIDIA driver is already up-to-date."
	exit
elif [[ "${INSTALLED_DRIVER}" == "${REQUESTED_DRIVER}" && -z "${UPGRADE_ONLY}" && -z "${LATEST}" ]]; then
	ohai "The requested driver ${REQUESTED_DRIVER} is already installed. Run \`bash $(basename "$0") --upgrade-only\` to upgrade."
	exit
elif [[ -n "${DRY_RUN}" ]]; then
	exit
fi

if [[ "${REQUESTED_DRIVER#nvidia-driver-}" -ge "${INSTALLED_DRIVER#nvidia-driver-}" ]]; then
	ohai "Upgrade the NVIDIA driver from ${INSTALLED_DRIVER} [${INSTALLED_DRIVER_VERSION}] to ${REQUESTED_DRIVER} [${REQUESTED_DRIVER_VERSION}]."
else
	ohai "Downgrade the NVIDIA driver from ${INSTALLED_DRIVER} [${INSTALLED_DRIVER_VERSION}] to ${REQUESTED_DRIVER} [${REQUESTED_DRIVER_VERSION}]."
fi

DM_SERVICES=()
for dm in gdm3 lightdm; do
	if service "${dm}" status &>/dev/null; then
		DM_SERVICES+=("${dm}")
	fi
done

if [[ "${#DM_SERVICES[@]}" -gt 0 ]]; then
	if [[ "${#DM_SERVICES[@]}" -gt 1 ]]; then
		warn "The following display manager services are running:"
	else
		warn "The following display manager service is running:"
	fi
	printf "  - %s\n" "${DM_SERVICES[@]}"
	echo "The service will be stopped during the installation which may shut down the GUI desktop. The service will be restarted after the installation."
fi

if [[ -z "${YES}" ]]; then
	ring_bell
	wait_for_user
fi

for dm in "${DM_SERVICES[@]}"; do
	exec_cmd "sudo service ${dm} stop"
	# shellcheck disable=SC2064
	trap "exec_cmd 'sudo service ${dm} start'" EXIT
done

MODULES="$(sudo lsmod | grep '^nvidia' | awk '{ print $1 }')"
MODULES="${MODULES//$'\n'/ }"
if [[ -n "${MODULES}" ]]; then
	exec_cmd "sudo modprobe -r -f ${MODULES}"
fi

sleep 1

if [[ -n "$(sudo lsof -t /dev/nvidia* 2>/dev/null)" ]]; then
	abort "Some processes are still running on GPU."
fi

if [[ -n "${INSTALLED_DRIVER}" ]]; then
	NVIDIA_PACKAGES="$(apt-list-nvidia-packages)"
	if [[ -n "${NVIDIA_PACKAGES}" ]]; then
		exec_cmd "sudo apt-mark unhold ${NVIDIA_PACKAGES}"
	fi
	if [[ "${INSTALLED_DRIVER}" == "${REQUESTED_DRIVER}" ]]; then
		exec_cmd "sudo apt-get install --only-upgrade --yes ${NVIDIA_PACKAGES}"
	else
		exec_cmd "sudo apt-get purge --yes ${NVIDIA_PACKAGES}"
	fi
fi

if [[ "${INSTALLED_DRIVER}" != "${REQUESTED_DRIVER}" ]]; then
	exec_cmd "sudo apt-get install --yes ${REQUESTED_DRIVER}"
fi

NVIDIA_PACKAGES="$(apt-list-nvidia-packages)"
if [[ -n "${NVIDIA_PACKAGES}" ]]; then
	exec_cmd "sudo apt-mark hold ${NVIDIA_PACKAGES}"
fi

exec_cmd 'nvidia-smi'