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

To run PSBot, simply run `bin/psbot`, or in your own code, run the code in the synopsis. Note that `PSBot.start` is blocking.

An example config file has been provided in psbot.json.example. This is to be copied over to `~/.config/psbot.json` and edited to suit your needs. Because of this, PSBot is not compatible with Windows.

The following are the available config options:

  * username

The username the bot should use.

  * password

If any, the password the bot should use.

  * avatar

The avatar the bot should use.

  * host

The URL of the server you wish to connect to.

  * port

The port of the server you wish to connect to.

  * ssl

Whether or not to enable connecting using SSL. Set to true if the port is 443.

  * serverid

The ID of the server you wish to connect to.

  * command

The character that should precede all commands.

  * rooms

The list of rooms the bot should join.

  * admins

The list of users who have admin access to the bot. Be wary of who you add to this list!

