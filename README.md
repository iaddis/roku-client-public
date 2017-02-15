## [DEPRECATED] roku-client-public (Plex Classic for Roku)

This repo and channel have been deprecated. Please install the official Plex version through the [Roku Channel Store](https://my.roku.com/account/add?channel=plex). The channel store is also available on your Roku device.

- [Plex for Roku Support](https://support.plex.tv/hc/en-us/sections/200305393-Roku)
- [Plex for Roku Forums](https://forums.plex.tv/categories/roku-streaming-players)

## Installation

You don't need to download or install anything from Roku, but you should take a look at Roku's
[developer site](http://www.roku.com/developer). In addition to the downloadable
PDF documentation, you can [browse the docs online](http://sdkdocs.roku.com/).
Roku's docs are well above average.

### Dev Mode

Before you can actually install Roku channels from source, you need to make
sure your Roku is in "dev" mode:

1. Using the Roku remote, press `Home-Home-Home-Up-Up-Right-Left-Right-Left-Right`
2. Choose to Enable the Installer

You only need to do this once, it will remain in dev mode. If you ever want to
exit dev mode you can use the same remote sequence.

### Building and Installing Locally

There's a Makefile that should take care of everything for you. You just need
to set an environment variable with the IP address of your Roku. Assuming
you're in a unix-like environment:

1. `export ROKU_DEV_TARGET=192.168.1.2` (substituting your IP address...)
2. `cd Plex`
3. `make install`

There are some additional targets in the Makefile, like `make rel install` to
build a release, but you don't generally need them. One other nicety is the
ability to take a screenshot using `make screenshot`.

**Note:** Some Roku versions are beginning to require HTTP authentication for
the installer. This is somewhat handled, but not necessarily robustly, so
you may need to make some tweaks. You can set environment variables for
`ROKU_DEV_USERNAME` and `ROKU_DEV_PASSWORD`, which default to `rokudev` and
`plex` respectively.

### Debugging

The Roku doesn't have logging per se, but dev channels are able to write
messages to a console that you can tail using telnet. It's as simple as

    telnet $ROKU_DEV_TARGET 8085


