#!/usr/bin/env bash
# Bounded Docker cleanup for a host whose slots share the Docker socket.
#
# Jobs leave stopped containers, anonymous service volumes, BuildKit cache and
# images behind, and nothing removes them: a host that is never cleaned fills
# its disk and every slot on it fails at once. Every step here removes only
# what no container is using, so it is safe while jobs run:
#
#   - stopped containers older than a day
#   - anonymous volumes no container references (named volumes are kept)
#   - dangling images
#   - build cache beyond GHA_BUILD_CACHE_MAX (least recently used goes first)
#   - unused images older than GHA_IMAGE_MAX_AGE, only once the root
#     filesystem is at GHA_DISK_PRUNE_PERCENT or more, so a host with room
#     keeps its pulled images and does not re-pull them every day
set -Eeuo pipefail

build_cache_max="${GHA_BUILD_CACHE_MAX:-20GB}"
image_max_age="${GHA_IMAGE_MAX_AGE:-168h}"
disk_prune_percent="${GHA_DISK_PRUNE_PERCENT:-70}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker-hygiene: no docker on this host, nothing to do"
  exit 0
fi

used_percent() {
  df --output=pcent / | tail -1 | tr -dc '0-9'
}

echo "docker-hygiene: root filesystem $(used_percent)% used before"
docker container prune -f --filter "until=24h"
docker volume prune -f
docker image prune -f
docker builder prune -f --max-used-space "${build_cache_max}"
if [[ "$(used_percent)" -ge "${disk_prune_percent}" ]]; then
  echo "docker-hygiene: at or above ${disk_prune_percent}%, removing unused images older than ${image_max_age}"
  docker image prune -af --filter "until=${image_max_age}"
fi
echo "docker-hygiene: root filesystem $(used_percent)% used after"
