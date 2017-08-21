# Unfollowerbot

Track Twitch follows and unfollows. Unfollowerbot tracks your followers and emails you with a daily digest of who followed and unfollowed you. You can self-host Unfollowerbot as a Docker container.

## Running

Twitch requires a Client ID for all API requests. [Register your app with Twitch](https://www.twitch.tv/kraken/oauth2/clients/new) to get a Client ID.

You can [choose a stable tag](https://hub.docker.com/r/schmich/unfollowerbot/tags) to use in place of `latest` below.

```bash
mkdir /srv/unfollowerbot && cd /srv/unfollowerbot
curl -o config.json https://raw.githubusercontent.com/schmich/unfollowerbot/master/config.json.tpl
# Edit config.json with your configuration.

docker run --name unfollowerbot \
  -d -v /srv/unfollowerbot:/etc/unfollowerbot:ro \
  --restart always schmich/unfollowerbot:latest
```

## License

Copyright &copy; 2015 Chris Schmich  
MIT License. See [LICENSE](LICENSE) for details.
