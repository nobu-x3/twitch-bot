# What is this?
This is a twitch bot that joins a channel, receives ALL the messages and pronounces them (text-to-speech).

# Dependencies
* [Piper](https://github.com/rhasspy/piper)

# Instructions
Compile it with `jai build.jai` and run the produced executable in `bin/twitch-bot`, or download the latest release.
Make sure to put the `env` file containing the environment variables in the `bin` folder.

# Environment variables
Create a new file called `env` and place it in the folder containing the executable.
The file should contain configuration in the following format:
```
CLIENTID=<your client id>
CLIENTSECRET=<your client secret>
USERNAME=<the bot's username>
PASSWORD=<see section below>
CHANNELNAME=#<name of the channel>
```
## PASSWORD variable
To obtain the password, before running the bot, you have use the browser to go to https://id.twitch.tv/oauth2/authorize?response_type=code&client_id=<client id>&redirect_uri=http://localhost:3000&scope=chat%3Aread+chat%3Aedit+channel%3Amoderate+whispers%3Aread+whispers%3Aedit
The resulting URL will contain a parameter `code`, e.g. `http://localhost:3000/?code=oq7jn9xjowb8evup9dupxu69s4uima&scope=chat%3Aread+chat%3Aedit+channel%3Amoderate+whispers%3Aread+whispers%3Aedit` - the `code` is `oq7jn9xjowb8evup9dupxu69s4uima`.
So, in the `env` file the `PASSWORD` field should be set as `PASSWORD=oq7jn9xjowb8evup9dupxu69s4uima`.
