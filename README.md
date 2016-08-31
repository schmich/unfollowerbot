# Unfollowerbot

Track Twitch follows and unfollows. Unfollowerbot tracks your followers and emails you with a daily digest of who followed and unfollowed you. You can self-host Unfollowerbot as a Docker container.

## Example Setup

```bash
mkdir /srv/unfollowerbot && cd /srv/unfollowerbot
curl -o config.json https://raw.githubusercontent.com/schmich/unfollowerbot/master/config.json.tpl
# Edit config.json, specify the account to track, whom to email, and whom to send email as.
docker run -d -v /srv/unfollowerbot:/etc/unfollowerbot:ro schmich/unfollowerbot:latest
# You can also pick a stable tag from https://hub.docker.com/r/schmich/unfollowerbot/tags
```
