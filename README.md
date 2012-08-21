rbIRCd
======

An IRC daemon implemented in pure Ruby.

rbIRCd is of mixed seriousness. The goal is to have a feature-rich server that
shouldn't crash often, though commands and connections may be dropped
occasionally due to the cheap error handling ;D

I plan to implement various [IRCv3](http://ircv3.atheme.org/) features, even
before they are official, in rbIRCd; in a way, this is going to be a prototyping
server for IRCv3. I'll probably use a feature branch though, don't worry.

Written by [danopia](http://danopia.net) for fun and science.

Implemented commands:
* NICK
* USER
* WHOIS
* JOIN *(doesn't take lists)*
* PART
* QUIT
* PRIVMSG
* NOTICE
* USERHOST
* PING
* PONG *(lulz, it doesn't do anything anyway)*
* NAMES
* OPER
* KILL
* TOPIC
* MODE *(still needs a ton of work)*
* LIST
* WHO
* KICK

Soon to be done:
* Ping timeouts
* Join channel list
* Modes
* Code needs to be split up across files
* Check for params to reduce errors
* Check for chanop etc. before accepting modes, topics
* INVITE
* AWAY
* IRCv3 *(TBD which parts)*

