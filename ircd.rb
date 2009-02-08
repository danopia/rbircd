#!/usr/bin/env ruby
#require 'gserver'
#require 'rubygems'
#require 'daemons'

#
# Copyright (C) 2001 John W. Small All Rights Reserved
#
# Author::        John W. Small
# Documentation:: Gavin Sinclair
# Licence::       Freeware.
#
# See the class GServer for documentation.
#

require "socket"
require "thread"

#
# GServer implements a generic server, featuring thread pool management,
# simple logging, and multi-server management.  See HttpServer in 
# <tt>xmlrpc/httpserver.rb</tt> in the Ruby standard library for an example of
# GServer in action.
#
# Any kind of application-level server can be implemented using this class.
# It accepts multiple simultaneous connections from clients, up to an optional
# maximum number.  Several _services_ (i.e. one service per TCP port) can be
# run simultaneously, and stopped at any time through the class method
# <tt>GServer.stop(port)</tt>.  All the threading issues are handled, saving
# you the effort.  All events are optionally logged, but you can provide your
# own event handlers if you wish.
#
# === Example
#
# Using GServer is simple.  Below we implement a simple time server, run it,
# query it, and shut it down.  Try this code in +irb+:
#
#   require 'gserver'
#
#   #
#   # A server that returns the time in seconds since 1970.
#   # 
#   class TimeServer < GServer
#     def initialize(port=10001, *args)
#       super(port, *args)
#     end
#     def serve(io)
#       io.puts(Time.now.to_i)
#     end
#   end
#
#   # Run the server with logging enabled (it's a separate thread).
#   server = TimeServer.new
#   server.audit = true                  # Turn logging on.
#   server.start 
#
#   # *** Now point your browser to http://localhost:10001 to see it working ***
#
#   # See if it's still running. 
#   GServer.in_service?(10001)           # -> true
#   server.stopped?                      # -> false
#
#   # Shut the server down gracefully.
#   server.shutdown
#   
#   # Alternatively, stop it immediately.
#   GServer.stop(10001)
#   # or, of course, "server.stop".
#
# All the business of accepting connections and exception handling is taken
# care of.  All we have to do is implement the method that actually serves the
# client.
#
# === Advanced
#
# As the example above shows, the way to use GServer is to subclass it to
# create a specific server, overriding the +serve+ method.  You can override
# other methods as well if you wish, perhaps to collect statistics, or emit
# more detailed logging.
#
#   connecting
#   disconnecting
#   starting
#   stopping
#
# The above methods are only called if auditing is enabled.
#
# You can also override +log+ and +error+ if, for example, you wish to use a
# more sophisticated logging system.
#
class IRCServer

  DEFAULT_HOST = "0.0.0.0"

  @@services = {}   # Hash of opened ports, i.e. services
  @@servicesMutex = Mutex.new

  def IRCServer.stop(port, host = DEFAULT_HOST)
    @@servicesMutex.synchronize {
      @@services[host][port].stop
    }
  end

  def IRCServer.in_service?(port, host = DEFAULT_HOST)
    @@services.has_key?(host) and
      @@services[host].has_key?(port)
  end

  def stop
    @connectionsMutex.synchronize  {
      if @tcpServerThread
        @tcpServerThread.raise "stop"
      end
    }
  end

  def stopped?
    @tcpServerThread == nil
  end

  def shutdown
    @shutdown = true
  end

  def join
    @tcpServerThread.join if @tcpServerThread
  end

  attr_reader :port, :host, :maxConnections
  attr_accessor :stdlog, :audit, :debug, :threads, :clients, :channels

  def connecting(client)
    addr = client.addr
    log("#{@host}:#{@port} client:#{addr[1]} " +
        "#{addr[2]}<#{addr[3]}> connect")
    true
  end

  def disconnecting(clientPort)
    log("#{@host}:#{@port} " +
      "client:#{clientPort} disconnect")
  end

  protected :connecting, :disconnecting

  def starting()
    log("#{@host}:#{@port} start")
  end

  def stopping()
    log("#{@host}:#{@port} stop")
  end

  protected :starting, :stopping

  def error(detail)
    log(detail.backtrace.join("\n"))
  end

  def log(msg)
    if @stdlog
      @stdlog.puts("[#{Time.new.ctime}] %s" % msg)
      @stdlog.flush
    end
  end

  def log_nick(nick, msg)
    log("#{@host}:#{@port} #{nick}\t%s" % msg)
  end

  protected :error, :log

  def initialize(port, host = DEFAULT_HOST, maxConnections = 20,
    stdlog = $stderr, audit = false, debug = false)
    @tcpServerThread = nil
    @port = port
    @host = host
    @maxConnections = maxConnections
    @clients = []
    @channels = []
    @threads = []
    @connectionsMutex = Mutex.new
    @connectionsCV = ConditionVariable.new
    @stdlog = stdlog
    @audit = audit
    @debug = debug
  end

  def start(maxConnections = -1)
    raise "running" if !stopped?
    @shutdown = false
    @maxConnections = maxConnections if maxConnections > 0
    @@servicesMutex.synchronize  {
      if IRCServer.in_service?(@port,@host)
        raise "Port already in use: #{host}:#{@port}!"
      end
      @tcpServer = TCPServer.new(@host,@port)
      @port = @tcpServer.addr[1]
      @@services[@host] = {} unless @@services.has_key?(@host)
      @@services[@host][@port] = self;
    }
    @tcpServerThread = Thread.new {
      begin
        starting if @audit
        while !@shutdown
          @connectionsMutex.synchronize  {
             while @clients.size >= @maxConnections
               @connectionsCV.wait(@connectionsMutex)
             end
          }
          client = IRCClient.new(@tcpServer.accept)
          @clients << client
          @threads << Thread.new(client)  { |myClient|
            begin
              myPort = myClient.addr[1]
              myClient.serve if !@audit or connecting(myClient)
            rescue => detail
              error(detail) if @debug
            ensure
              begin
                myClient.close
              rescue
              end
              @connectionsMutex.synchronize {
                @clients.delete(myClient)
                @threads.delete(Thread.current)
                @connectionsCV.signal
              }
              disconnecting(myPort) if @audit
            end
          }
        end
      rescue => detail
        error(detail) if @debug
      ensure
        begin
          @tcpServer.close
        rescue
        end
        if @shutdown
          @connectionsMutex.synchronize  {
             while @connections.size > 0
               @connectionsCV.wait(@connectionsMutex)
             end
          }
        else
          @threads.each { |c| c.raise "stop" }
        end
        @tcpServerThread = nil
        @@servicesMutex.synchronize  {
          @@services[@host].delete(@port)
        }
        stopping if @audit
      end
    }
    self
  end

	def find_nick(nick)
		target = nick.downcase
		@clients.each do |client|
			return client if client.nick.downcase == target
		end
		nil
	end

	def find_channel(channel)
		target = channel.downcase
		@channels.each do |channel|
			return channel if channel.name.downcase == target
		end
		nil
	end
end

class IRCChannel
	attr_reader :name, :users, :ops, :voice, :bans
	attr_reader :modes, :mode_timestamp
	attr_reader :topic, :topic_author, :topic_timestamp
	
	def initialize(name)
		@name = name
		@users = []
		@ops = []
		@voice = []
		@bans = []
		
		@modes = 'ns'
		@mode_timestamp = Time.now.gmtime.to_i
		
		@topic = nil
		@topic_author = nil
		@topic_timestamp = nil
	end
	
	
end

class IRCClient
  attr_reader :nick, :ident, :realname, :io, :addr, :ip, :host
  #attr_accessor :stdlog, :audit, :debug
  
	def initialize(io)
		@nick = '*'
		@ident = nil
		@realname = nil
		@io = io
		
		@addr = io.peeraddr
    @ip = @addr[3]
		@host = @addr[2]
		
    io.puts ":pentagon.danopia.net NOTICE AUTH :*** Looking up your hostname...\n:pentagon.danopia.net NOTICE AUTH :*** Found your hostname"
	end

	def is_registered?
		@nick != '*' and @ident != nil
	end
	def check_registration()
		send_motd if is_registered?
		puts ":#{@nick} MODE #{@nick} :+iwx"
	end
 
	def close(reason = 'Connection reset by peer')
		$server.log_nick(@nick, "User disconnected (#{reason}).")
		
		updated_users = [self]
		$server.channels.each do |channel|
			if channel.users.include?(self)
				channel.users.each do |user|
					if !(updated_users.include?(user))
						user.puts ":#{path} QUIT :" + reason
						updated_users << user
					end
				end
				channel.users.delete(self)
			end
		end
		
		begin
			puts("ERROR :Closing Link: #{@nick}[#{@ip}] (#{reason})")
			@io.close
		rescue
		end
	end
	
	def puts(msg)
		@io.puts msg
	end
	
	def path
		"#{@nick}!#{@ident}@#{@host}"
	end
	
	def send_names(channel)
		nicks = []
		channel.users.each do |user|
			nicks << user.nick
		end
		puts ":pentagon.danopia.net 353 #{@nick} = #{channel.name} :#{nicks.join(' ')}"
		puts ":pentagon.danopia.net 366 #{@nick} #{channel.name} :End of /NAMES list."
	end
	
	def send_motd()
		puts ":pentagon.danopia.net 001 #{@nick} :Welcome to the FBI Pentagon IRC Network #{path}
:pentagon.danopia.net 002 #{@nick} :Your host is pentagon.danopia.net, running version Unreal3.2.7
:pentagon.danopia.net 003 #{@nick} :This server was created Tue Dec 23 2008 at 15:18:59 EST
:pentagon.danopia.net 004 #{@nick} pentagon.danopia.net RubyIRCd0.1.0 iowghraAsORTVSxNCWqBzvdHtGp lvhopsmntikrRcaqOALQbSeIKVfMCuzNTGj
:pentagon.danopia.net 005 #{@nick} NAMESX SAFELIST HCN MAXCHANNELS=10 CHANLIMIT=#:10 MAXLIST=b:60,e:60,I:60 NICKLEN=30 CHANNELLEN=32 TOPICLEN=307 KICKLEN=307 AWAYLEN=307 MAXTARGETS=20 WALLCHOPS :are supported by this server
:pentagon.danopia.net 005 #{@nick} WATCH=128 SILENCE=15 MODES=12 CHANTYPES=# PREFIX=(qaohv)~&@%+ CHANMODES=beI,kfL,lj,psmntirRcOAQKVCuzNSMTG NETWORK=FBI-Pentagon CASEMAPPING=ascii EXTBAN=~,cqnr ELIST=MNUCT STATUSMSG=~&@%+ EXCEPTS INVEX :are supported by this server
:pentagon.danopia.net 005 #{@nick} CMDS=KNOCK,MAP,DCCALLOW,USERIP :are supported by this server
:pentagon.danopia.net 251 #{@nick} :There are 1 users and 2 invisible on 1 servers
:pentagon.danopia.net 252 #{@nick} 1 :operator(s) online
:pentagon.danopia.net 254 #{@nick} 4 :channels formed
:pentagon.danopia.net 255 #{@nick} :I have 3 clients and 0 servers
:pentagon.danopia.net 265 #{@nick} :Current Local Users: 3  Max: 9
:pentagon.danopia.net 266 #{@nick} :Current Global Users: 3  Max: 5
:pentagon.danopia.net 375 #{@nick} :- pentagon.danopia.net Message of the Day - 
:pentagon.danopia.net 372 #{@nick} :- 24/12/2008 14:53
:pentagon.danopia.net 372 #{@nick} :- 4FFFFFFFFFFFFFFFFFFFFFFFF3BBBBBBBBBBBBBBBBBB   2IIIIIIIIIIIIIIIII
:pentagon.danopia.net 372 #{@nick} :- 4F::::::::::::::::::::::F3B:::::::::::::::::B  2I:::::::::::::::I
:pentagon.danopia.net 372 #{@nick} :- 4F::::::::::::::::::::::F3B:::::::BBBBBB:::::B 2I:::::::::::::::I
:pentagon.danopia.net 372 #{@nick} :- 4FF:::::::FFFFFFFFFF::::F3BB::::::B     B:::::B2IIIII:::::::IIIII
:pentagon.danopia.net 372 #{@nick} :- 4  F::::::F        FFFFFF3  B:::::B     B:::::B2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F::::::F              3  B:::::B     B:::::B2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F:::::::FFFFFFFFFFF   3  B:::::BBBBBB:::::B 2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F:::::::::::::::::F   3  B::::::::::::::BB  2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F:::::::::::::::::F   3  B:::::BBBBBB:::::B 2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F:::::::FFFFFFFFFFF   3  B:::::B     B:::::B2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F::::::F              3  B:::::B     B:::::B2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4  F::::::F              3  B:::::B     B:::::B2     I:::::I  
:pentagon.danopia.net 372 #{@nick} :- 4FF::::::::FF            3BB::::::BBBBBB::::::B2IIIII:::::::IIIII
:pentagon.danopia.net 372 #{@nick} :- 4F::::::::::F            3B::::::::::::::::::B 2I:::::::::::::::I
:pentagon.danopia.net 372 #{@nick} :- 4F::::::::::F            3B:::::::::::::::::B  2I:::::::::::::::I
:pentagon.danopia.net 372 #{@nick} :- 4FFFFFFFFFFFF            3BBBBBBBBBBBBBBBBBB   2IIIIIIIIIIIIIIIII
:pentagon.danopia.net 372 #{@nick} :- 
:pentagon.danopia.net 372 #{@nick} :-         .'.
:pentagon.danopia.net 372 #{@nick} :-       .'   '.                           _                           
:pentagon.danopia.net 372 #{@nick} :-     .'       '.      ____  _____ ____ _| |_ _____  ____  ___  ____  
:pentagon.danopia.net 372 #{@nick} :-   .'    .'.    '.   |  _ \\| ___ |  _ (_   _|____ |/ _  |/ _ \\|  _ \\ 
:pentagon.danopia.net 372 #{@nick} :- .'    .'   '.    '. | |_| | ____| | | || |_/ ___ ( (_| | |_| | | | |
:pentagon.danopia.net 372 #{@nick} :- \\     \\     /     / |  __/|_____)_| |_| \\__)_____|\\___ |\\___/|_| |_|
:pentagon.danopia.net 372 #{@nick} :-  \\     \\___/     /  |_|                          (_____|            
:pentagon.danopia.net 372 #{@nick} :-   \\             /
:pentagon.danopia.net 372 #{@nick} :-    \\           /
:pentagon.danopia.net 372 #{@nick} :-     \\_________/
:pentagon.danopia.net 372 #{@nick} :- 
:pentagon.danopia.net 372 #{@nick} :- --------------------------------------------------------------------
:pentagon.danopia.net 372 #{@nick} :- 
:pentagon.danopia.net 372 #{@nick} :- main message relay of FBI version control informant.
:pentagon.danopia.net 372 #{@nick} :- beware! this is a private server!
:pentagon.danopia.net 372 #{@nick} :- 
:pentagon.danopia.net 372 #{@nick} :- run by danopia
:pentagon.danopia.net 376 #{@nick} :End of /MOTD command.
"
	end
	
  def serve()
		loop do
			raw = @io.gets
			if raw == '' or raw == nil
				puts "FAILURE"
			$server.log_nick(@nick, "FAILURE")
			end
			raw_args = raw.split(' ')
			command = raw_args[0].downcase
			$server.log_nick(@nick, command)
			case command
			
				when 'user'
					if raw_args.size < 5
						puts ":pentagon.danopia.net 461 #{@nick} USER :Not enough parameters"
					elsif is_registered?
						puts ":pentagon.danopia.net 462 #{@nick} :You may not reregister"
					else
						@ident = raw_args[1]
						@realname = raw_args[4]
						check_registration
					end
			
				when 'nick'
					if raw_args.size < 2 || raw_args[1].size < 1
						puts ":pentagon.danopia.net 431 #{@nick} :No nickname given"
					elsif $server.find_nick(raw_args[1])
						puts ":pentagon.danopia.net 433 #{@nick} #{raw_args[1]} :Nickname is already in use."
					elsif is_registered?
						newnick = raw_args[1]
						puts ":#{path} NICK :" + newnick
						
						updated_users = [self]
						$server.channels.each do |channel|
							if channel.users.include?(self)
								channel.users.each do |user|
									if !(updated_users.include?(user))
										user.puts ":#{path} NICK :" + newnick
										updated_users << user
									end
								end
							end
						end
						
						@nick = newnick
					else
						@nick = raw_args[1]
						check_registration
					end
					
				when 'whois'
					target = $server.find_nick(raw_args[1])
					if target == nil
						puts ":pentagon.danopia.net 401 #{@nick} #{raw_args[1]} :No such nick/channel"
					else
					puts ":pentagon.danopia.net 311 #{@nick} #{target.nick} #{target.ident} #{target.host} * :#{target.realname}
:pentagon.danopia.net 378 #{@nick} #{target.nick} :is connecting from *@#{target.addr[2]} #{target.ip}
:pentagon.danopia.net 312 #{@nick} #{target.nick} pentagon.danopia.net :FBI Informational Backbone Server
:pentagon.danopia.net 317 #{@nick} #{target.nick} 2 1233972544 :seconds idle, signon time
:pentagon.danopia.net 318 #{@nick} #{target.nick} :End of /WHOIS list.
"
					end
					
				when 'privmsg', 'notice'
					target = $server.find_channel(raw_args[1])
					if target == nil
						target = $server.find_nick(raw_args[1])
						if target == nil
							puts ":pentagon.danopia.net 401 #{@nick} #{raw_args[1]} :No such nick/channel"
						else
							target.puts ":#{path} #{raw}"
						end
					else
						target.users.each do |user|
							user.puts ":#{path} #{raw}" unless user == self
						end
					end
					
				when 'join'
					channel = $server.find_channel(raw_args[1])
					if channel == nil
						channel = IRCChannel.new(raw_args[1].downcase)
						$server.channels << channel
					end
					if !(channel.users.include?(self))
						channel.users << self
						channel.users.each do |user|
							user.puts ":#{path} JOIN :#{channel.name}"
						end
						send_names(channel)
					end
					
				when 'part'
					channel = $server.find_channel(raw_args[1])
					if channel == nil
						puts ":pentagon.danopia.net 403 #{@nick} #{raw_args[1]} :No such channel"
					elsif !(channel.users.include?(self))
						puts ":pentagon.danopia.net 403 #{@nick} #{raw_args[1]} :No such channel"
					else
						channel.users.each do |user|
							user.puts ":#{path} PART #{channel.name} :" + 'Leaving'
						end
						channel.users.delete(self)
					end
					
				when 'names'
					channel = $server.find_channel(raw_args[1])
					send_names(channel)
					
				when 'quit'
					close('Leaving')
					return
			
				when 'pong'
				when 'ping'
					target = raw_args[1]
					puts ":pentagon.danopia.net PONG pentagon.danopia.net :#{target}"
					
				when 'userhost'
					target = $server.find_nick(raw_args[1])
					if target == nil
						puts ":pentagon.danopia.net 401 #{@nick} #{raw_args[1]} :No such nick/channel"
					else
						puts ":pentagon.danopia.net 302 #{@nick} :#{target.nick}=+#{target.ident}@#{target.ip}"
					end
					
				else
					puts ":pentagon.danopia.net 421 #{@nick} #{command} :Unknown command"
			end
		end
  end
end

# Daemons.daemonize
$server = IRCServer.new(7331, '0.0.0.0')
$server.audit = true
$server.debug = true
$server.start
loop do
	sleep 60 
	$server.clients.each do |value|
		begin
			value.puts 'PING :pentagon.danopia.net'
		rescue => detail
			value.close
			$server.clients.delete(value)
		end	
	end
end
