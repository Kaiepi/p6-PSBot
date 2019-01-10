NAME
====

PSBot - Pokémon Showdown chat bot

SYNOPSIS
========

    use PSBot;

    my PSBot $bot .= new;
    $bot.start;

DESCRIPTION
===========

PSBot is a Pokemon Showdown bot that will specialize in easily allowing the user to customize how the bot responds to messages.

To run PSBot, simply run `bin/psbot`, or in your own code, run the code in the synopsis. Note that `PSBot.start` is blocking. Debug logging can be enabled by setting the `DEBUG` environment variable to 1.

An example config file has been provided in `psbot.json.example`. This is to be copied over to `~/.config/psbot.json` (`%LOCALAPPDATA%\PSBot\psbot.json` on Windows) and edited to suit your needs.

The following are the available config options:

  * Str *username*

The username the bot should use.

  * Str *password*

The password the bot should use. Set to null if no password is needed.

  * Str *avatar*

The avatar the bot should use.

  * Str *host*

The URL of the server you wish to connect to.

  * Int *port*

The port of the server you wish to connect to.

  * Bool *ssl*

Whether or not to enable connecting using SSL. Set to true if the port is 443.

  * Str *serverid*

The ID of the server you wish to connect to.

  * Str *command*

The character that should precede all commands.

  * Set *rooms*

The list of rooms the bot should join.

  * Set *admins*

The list of users who have admin access to the bot. Be wary of who you add to this list!

  * Int *max_reconnect_attempts*

The maximum consecutive reconnect attempts allowed before the connection will throw.

  * Str *git*

The link to the GitHub repo for the bot.

