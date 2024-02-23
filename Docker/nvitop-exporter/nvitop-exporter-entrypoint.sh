#!/bin/bash

set -euo pipefail

NVITOP_EXPORTER=$(readlink -f $(which nvitop-exporter))
# NVITOP_EXPORTER=nvitop-exporter

# Not sure if this needed
# We want to setcap only when the container is started with the right caps
# if [ -z "$NO_SETCAP" ]; then
#    if setcap 'cap_sys_admin=+ep' $NVITOP_EXPORTER; then
#       if ! $NVITOP_EXPORTER -v 1>/dev/null 2>/dev/null; then
#          >&2 echo "Warning #2: nvitop-exporter doesn't have sufficient privileges to expose profiling metrics. To get profiling metrics with nvitop-exporter, use --cap-add SYS_ADMIN"
#          setcap 'cap_sys_admin=-ep' $NVITOP_EXPORTER
#       fi
#    else
#       >&2 echo "Warning #1: nvitop-exporter doesn't have sufficient privileges to expose profiling metrics. To get profiling metrics with nvitop-exporter, use --cap-add SYS_ADMIN"
#    fi
# fi

# Pass the command line arguments to nvtiop-exporter
set -- $NVITOP_EXPORTER "$@"

exec "$@"
