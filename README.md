[![Build Status](https://travis-ci.org/Kaiepi/p6-PSBot.svg?branch=master)](https://travis-ci.org/Kaiepi/p6-PSBot)

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

PSBot is a Pokémon Showdown chat bot. While many, many chat bots for Pokémon Showdown already exist, PSBot has several advantages over others:

Better account management
-------------------------

All requests made to the login server are handled using an instance of the `PSBot::LoginServer` class, which is available in all of PSBot's code that is invoked from the parser, rather than just the parts of the parser that need it. The nick command is an example of something that would be more difficult to implement in other bots.

PSBot also uses the `upkeep` login server action to handle logging in after reconnects. This is somewhat faster than using the `login` action.

User and room tracking
----------------------

PSBot keeps track of all information related to users and rooms that is possible for the bot to obtain at any rank and relevant for implementing features. For example, this means that it is possible to implement commands that only autoconfirmed users can use with PSBot.

Powerful response handling
--------------------------

PSBot has `PSBot::Response` and `PSBot::ResponseHandler`, which are abstractions for dealing with responses to messages received from the server. `PSBot::ResponseHandler` adds a `reply` method to whatever type uses it. This method accepts a message (a `Result` of some kind), which can be any of the following:

  * a string

This is how you'd respond normally.

  * a list of `Result`

This is how you'd respond if you want to send multiple messages in one response.

  * an object that can be awaited (the result being another `Result`)

This is how you'd respond when what should be sent as a response needs to be evaluated asynchronously.

  * a replier (the return value of another call to `PSBot::ResponseHandler.reply`)

This is how you'd respond in combination with lists of `Result` when you need to override what user or room you're sending a response to (like when you want to PM a user, then send to a room).

Better command handling
-----------------------

Commands in PSBot are a combination of a method and command metadata. At the moment, this includes:

  * whether or not the command requires you to be a bot administrator

  * whether or not the command requires autoconfirmed status

  * whether the commnd can be used in rooms, PMs, or everywhere

  * what rank the command should require by default

PSBot's command handler uses this information to automatically respond with why a command can't be used if the user (and, optionally, the room) the command was used in don't meet the criteria the command was defined with. This means you don't have to write any boilerplate for anything related to this yourself; PSBot will handle it for you.

Games
-----

PSBot has a games API (`PSBot::Game`). and it supports features for games that not even Pokémon Showdown itself supports, like the ability to play one game in an arbitrary number of rooms, and the ability to make games playable in PMs.

Rules
-----

Rules make it possible to change how PSBot parses messages without needing to fork the bot. They are a combination of a regex and a routine for parsing `|c:|`, `|pm|`, `|html|`, `|popup|`, and `|raw|` messages (at the moment; more supported message types are in the works). For example, PSBot's command parser and room invite handler are implemented as rules.

Testable
--------

PSBot is designed in such a way that it's possible to unit test. Users, rooms, games, responses, response handlers, and commands are the features of PSBot that currently have unit tests, and tests for other parts of the bot are planned. This means developing with PSBot should be faster and easier to do than with other bots.

INSTALLATION
============

You will need to have [Perl 6 and zef](https://rakudo.org) installed, as well as SQLite. Once this is done, refer to the section pertaining to your OS for instruction on how to install PSBot itself.

Windows
-------

Clone this repository, then run this from the repository's directory in a terminal:

    zef install .

Next, you will need to create an empty file for PSBot's database:

    fsutil file createnew resources\database.sqlite3 0

Afterwards, you will need to configure PSBot. Refer to the config section of this README for information on how to do this.

Finally, to start the bot, run:

    psbot

Mac OS X, Linux, *BSD, and Solaris
----------------------------------

Clone this repository, then run this from the repository's directory in a terminal:

    $ zef install .

Next, you will need to create an empty file for PSBot's database:

    $ touch resources/database.sqlite3

Afterwards, you will need to configure PSBot. Refer to the configuration section of this README for information on how to do this.

Finally, to start the bot, run:

    $ psbot

CONFIGURATION
=============

An example config file has been provided in `config.json.example`. This is to be copied over to `~/.config/PSBot/config.json` (`%LOCALAPPDATA%\PSBot\config.json` on Windows) and edited to suit your needs.

These are the config options available:

  * Str *username*

The username the bot should use. Set to null if the bot should use a guest username.

  * Str *password*

The password the bot should use. Set to null if no password is needed.

  * Str *avatar*

The avatar the bot should use. Set to null if a random avatar should be used.

  * Str *status*

The status the bot should use. Set to null if no status should be used.

  * Str *host*

The URL of the server you wish to connect to.

  * Int *port*

The port of the server you wish to connect to.

  * Str *serverid*

The ID of the server you wish to connect to.

  * Str *command*

The command string that should precede all commands.

  * Set *rooms*

The list of rooms the bot should join.

  * Set *admins*

The list of users who have admin access to the bot. Be wary of who you add to this list!

  * Int *max_reconnect_attempts*

The maximum consecutive reconnect attempts allowed before the connection will throw.

  * Str *git*

The link to the GitHub repo for the bot.

  * Str *dictionary_api_id*

The API ID for Oxford Dictionary. Set to null if you don't want to use the dictionary command.

  * Str *dictionary_api_key*

The API key for Oxford Dictionary. Set to null if you don't want to use the dictionary command.

  * Str *youtube_api_key*

The API key for Youtube. Set to null if you don't want to use the youtube command.

  * Str *translate_api_key*

The API key for Google Translate. Set to null if you don't want to use the translate and badtranslate commands.

DEBUGGING
=========

PSBot features a debug logger, which is active if the `PSBOT_DEBUG` environment variable is set appropriately. PSBot uses a bitmask to determine which debug log types should be made. To enable debug logging, set `PSBOT_DEBUG` to `0` to start out with, then follow what the instructions for using each debug log type you want below say (you should end up with a number between `1` and `15`):

  * [DEBUG]

This is used to log generic debug messages. To enable this type of debug logging, XOR `PSBOT_DEBUG` with 1.

  * [CONNECTION]

This is used to log when the bot connects to or disconnects from the server. To enable this type of debug logging, XOR `PSBOT_DEBUG` with 2.

  * [SEND]

This is used to log messages sent to the server. To enable this type of debug logging, XOR `PSBOT_DEBUG` with 4.

  * [RECEIVE]

This is used to log messages received from the server. To enable this type of debug logging, XOR `PSBOT_DEBUG` with 8.

