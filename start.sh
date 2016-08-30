#!/bin/sh

# Clear existing snapshots.
rm -rf /srv/unfollowerbot/snapshots

# Run the snapshot once.
ruby /srv/unfollowerbot/snapshot.rb /etc/unfollowerbot/config.json

# Set time zone info.
tz=`jq -r .time_zone /etc/unfollowerbot/config.json`
cp /usr/share/zoneinfo/$tz /etc/localtime
echo "$tz" > /etc/timezone

exec /usr/sbin/crond -f
