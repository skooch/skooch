# Sonos utilities (soco-cli wrappers)

check_if_refresh_sonos() {
  local SPEAKERS_MODIFIED=$(date -r "$HOME/.soco-cli/speakers_v2.pickle" +%s)
  local CURRENT_DATE=$(date +%s)
  local DIFFERENCE=$(($CURRENT_DATE - $SPEAKERS_MODIFIED))
  if [ $DIFFERENCE -gt 43200 ]; then
    echo "One moment, updating sonos speaker list..."
    sonos-discover -t 256 -n 1.0 -m 24 >> /dev/null
  fi
}

stfu-list() {
  check_if_refresh_sonos
  echo "Your currently available speakers are:"
  sonos-discover -p | tail -n +6
}

stfu() {
  check_if_refresh_sonos
  echo "Shushing all Sonos speakers..."
  sonos _all_ vol 0
}

stfu-eng() {
  check_if_refresh_sonos
  echo "Shushing eng speakers..."
  sonos "Engineering & Product" vol 0
}

stfu-kitchen() {
  check_if_refresh_sonos
  echo "Shushing kitchen speakers..."
  sonos "Kitchen" vol 0
}

stfu-allhands() {
  check_if_refresh_sonos
  echo "Shushing all hands speakers..."
  sonos "All Hands" vol 0
}

unstfu() {
  check_if_refresh_sonos
  echo "Restoring volume on all Sonos speakers..."
  sonos _all_ vol 30
}

stfu-play() {
  sonos kitchen play_sharelink $1
}

stfu-nowplaying() {
  sonos kitchen track | tail -n +3
}
