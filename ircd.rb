#!/usr/bin/env ruby
#require 'gserver'
#require 'rubygems'
#require 'daemons'

#
# Most of the IRCServer class is from GServer
# GServer is copyright (C) 2001 John W. Small
#

require 'socket'
require 'thread'
require 'yaml'

#
# IRCServer implements an irc server, featuring thread pool management,
# simple logging, and multi-server management.
#
# Several _services_ (i.e. one service per TCP port) can be
# run simultaneously, and stopped at any time through the class method
# <tt>IRCServer.stop(port)</tt>.  All the threading issues are handled, saving
# you the effort.  All events are optionally logged, but you can provide your
# own event handlers if you wish.
#
# === Example
#
# Using IRCServer is simple.  Below we run an IRC server.  Try this code:
#
#   # Run the server with logging enabled (it's a separate thread).
#   server = IRCServer.new
#   server.audit = true                  # Turn logging on.
#   server.start 
#
#   # *** Now point your IRC client to localhost:6667 to see it working ***
#
#   # See if it's still running. 
#   GServer.in_service?(6667)            # -> true
#   server.stopped?                      # -> false
#
#   # Shut the server down gracefully.
#   server.shutdown
#   
#   # Alternatively, stop it immediately.
#   IRCServer.stop(6667)
#   # or, of course, "server.stop".
#
class IRCServer

  DEFAULT_HOST = "0.0.0.0"

  @@services = {}   # Hash of opened services
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
  attr_accessor :stdlog, :audit, :debug, :threads, :clients, :channels, :name


  def connecting(client)
    addr = client.addr
    log "#{@host}:#{@port} client:#{addr[1]} #{addr[2]}<#{addr[3]}> connect"
    true
  end

  def disconnecting(clientPort)
    log "#{@host}:#{@port} client:#{clientPort} disconnect"
  end
  protected :connecting, :disconnecting


  def starting()
    log "#{@host}:#{@port} start"
  end

  def stopping()
    log "#{@host}:#{@port} stop"
  end
  protected :starting, :stopping


  def error(detail)
    log detail.backtrace.join("\n")
  end

  def log(msg)
    if @stdlog
      @stdlog.puts "[#{Time.new.ctime}] %s" % msg
      @stdlog.flush
    end
  end
  protected :error, :log


  def log_nick(nick, msg)
    log "#{@host}:#{@port} #{nick}\t%s" % msg
  end

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
	attr_reader :topic, :topic_timestamp
	attr_accessor :topic_author
	
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
	
	def send_to_all(msg)
		users.each do |user|
			user.puts msg
		end
	end
	def send_to_all_except(nontarget, msg)
		users.each do |user|
			user.puts msg unless user == nontarget
		end
	end
	
	def topic=(topic)
		@topic = topic
		@topic_timestamp = Time.now
	end
	
end

class IRCClient
  attr_reader :nick, :ident, :realname, :io, :addr, :ip, :host, :dead
  attr_accessor :opered
  
	def initialize(io)
		@nick = '*'
		@ident = nil
		@realname = nil
		@io = io
		@dead = false
		@opered = false
		
		@addr = io.peeraddr
    @ip = @addr[3]
		@host = @addr[2]
		
    puts ":#{$server.name} NOTICE AUTH :*** Looking up your hostname..."
    puts ":#{$server.name} NOTICE AUTH :*** Found your hostname"
	end

	def is_registered?
		@nick != '*' and @ident != nil
	end
	def check_registration()
		send_welcome_flood if is_registered?
		puts ":#{@nick} MODE #{@nick} :+iwx"
	end
 
	def close(reason = 'Client quit')
		$server.log_nick(@nick, "User disconnected (#{reason}).")
		
		if !@dead
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
			@dead = true
		end
		
		begin
			puts "ERROR :Closing Link: #{@nick}[#{@ip}] (#{reason})"
			@io.close
		rescue
		end
	end
	def kill(killer, reason = 'Client quit')
		puts(":#{killer.path} KILL #{@nick} :#{$server.name}!#{killer.host}!#{killer.nick} (#{reason})")
		close reason
	end
	def skill(reason = 'Client quit')
		puts(":#{$server.name} KILL #{@nick} :#{$server.name} (#{reason})")
		close reason
	end
	
	def puts(msg)
		@io.puts msg
	end
	
	def put_snumeric(numeric, text)
		puts [':' + $server.name, numeric, @nick, text].join(' ')
	end
	
	def path
		"#{@nick}!#{@ident}@#{@host}"
	end
	
	def send_welcome_flood()
		put_snumeric '001', ":Welcome to the #{Config.network_name} IRC Network #{path}"
		put_snumeric '002', ":Your host is #{$server.name}, running version RubyIRCd0.1.0"
		put_snumeric '003', ":This server was created Tue Dec 23 2008 at 15:18:59 EST"
		put_snumeric '004', "#{$server.name} RubyIRCd0.1.0 iowghraAsORTVSxNCWqBzvdHtGp lvhopsmntikrRcaqOALQbSeIKVfMCuzNTGj"

		send_version
		send_lusers
		send_motd
	end
	
	def send_version(detailed=false)
		if detailed
			put_snumeric 351, "RubyIRCd0.1.0. #{$server.name} :FhiXeOoZE [Linux box 2.6.18-128.1.1.el5.028stab062.3 #1 SMP Sun May 10 18:54:51 MSD 2009 i686=2309]"
			puts ":#{$server.name} NOTICE #{@nick} :OpenSSL 0.9.8k 25 Mar 2009"
			puts ":#{$server.name} NOTICE #{@nick} :zlib 1.2.3"
			puts ":#{$server.name} NOTICE #{@nick} :libcurl/7.19.4 GnuTLS/2.6.6 zlib/1.2.3 c-ares/1.6.0 libssh2/0.18"
		end
		put_snumeric '005', 'NAMESX SAFELIST HCN MAXCHANNELS=10 CHANLIMIT=#:10 MAXLIST=b:60,e:60,I:60 NICKLEN=30 CHANNELLEN=32 TOPICLEN=307 KICKLEN=307 AWAYLEN=307 MAXTARGETS=20 WALLCHOPS :are supported by this server'
		put_snumeric '005', "WATCH=128 SILENCE=15 MODES=12 CHANTYPES=# PREFIX=(qaohv)~&@%+ CHANMODES=beI,kfL,lj,psmntirRcOAQKVCuzNSMTG NETWORK=#{Config.network_name.gsub(' ', '-')} CASEMAPPING=ascii EXTBAN=~,cqnr ELIST=MNUCT STATUSMSG=~&@%+ EXCEPTS INVEX :are supported by this server"
		put_snumeric '005', 'CMDS=KNOCK,MAP,DCCALLOW,USERIP :are supported by this server'
	end
	
	def send_lusers
		put_snumeric 251, ":There are 1 users and 2 invisible on 1 servers"
		put_snumeric 252, "1 :operator(s) online"
		put_snumeric 254, "4 :channels formed"
		put_snumeric 255, ":I have 3 clients and 0 servers"
		put_snumeric 265, ":Current Local Users: 3  Max: 9"
		put_snumeric 266, ":Current Global Users: 3  Max: 5"
	end

	def get_motd
		motd = nil
		begin
			filename = Config.motd_file
			return File.new(filename).read
		rescue
		end
		
		begin
			program = Config.motd_program
			program = program.gsub('%n', @nick.gsub(/([^a-zA-Z0-9])/, '\\\1'))
			return `#{program}` # TODO: Do it the right way
		rescue
		end
		
		nil
	end
	
	def send_motd
		motd = get_motd
		
		if motd
			put_snumeric 375, ":- #{$server.name} Message of the Day -"
			motd.each_line do |line|
				put_snumeric 372, ':- ' + line
			end
			put_snumeric 376, ':End of /MOTD command.'
		else
			put_snumeric 422, ':MOTD File is missing'
		end
	end
	
	def join(channel)
		return if channel.users.include?(self)
		channel.users << self
		channel.users.each do |user|
			user.puts ":#{path} JOIN :#{channel.name}"
		end
		send_topic(channel)
		send_names(channel)
		
		#<< JOIN #bitcast
		#>> :danopia!danopia@danopia::EighthBit::staff JOIN :#bitcast
		#<< MODE #bitcast
		#<< WHO #bitcast
		#>> :Silicon.EighthBit.net 332 danopia #bitcast :Interested in a slot for Episode 1? See http://is.gd/1vAro for available slots | Think you could do one of these topics on an upcoming episode? http://is.gd/1vAtA  - Let us know!
		#>> :Silicon.EighthBit.net 333 danopia #bitcast CodeBlock 1247378633
		#>> :Silicon.EighthBit.net 353 danopia = #bitcast :danopia nixeagle @CodeBlock @ChanServ 
		#>> :Silicon.EighthBit.net 366 danopia #bitcast :End of /NAMES list.
		#>> :Silicon.EighthBit.net 324 danopia #bitcast +nt 
		#>> :Silicon.EighthBit.net 329 danopia #bitcast 1247378376
		#>> :Silicon.EighthBit.net 352 danopia #bitcast danopia danopia::EighthBit::staff Silicon.EighthBit.net danopia Hr* :0 Daniel Danopia
		#>> :Silicon.EighthBit.net 352 danopia #bitcast nixeagle 9F3ADEED.AC9A3767.180762F4.IP Silicon.EighthBit.net nixeagle Gr* :0 James
		#>> :Silicon.EighthBit.net 352 danopia #bitcast CodeBlock CodeBlock::EighthBit::staff Platinum.EighthBit.net CodeBlock Hr*@ :1 CodeBlock
	end
	def send_topic(channel)
		return unless channel.topic
		put_snumeric 332, channel.name + ' :' + channel.topic
		put_snumeric 333, "#{channel.name} #{channel.topic_author} 1247378633"
	end
	def send_names(channel)
		nicks = []
		channel.users.each do |user|
			nicks << user.nick
		end
		put_snumeric 353, "= #{channel.name} :#{nicks.join(' ')}"
		put_snumeric 366, channel.name + ' :End of /NAMES list.'
	end
	
  def serve
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
						put_snumeric 461, 'USER :Not enough parameters'
					elsif is_registered?
						put_snumeric 462, ':You may not reregister'
					else
						@ident = raw_args[1]
						@realname = raw_args[4]
						check_registration
					end
			
				when 'nick'
					if raw_args.size < 2 || raw_args[1].size < 1
						put_snumeric 431, ':No nickname given'
					elsif $server.find_nick(raw_args[1])
						put_snumeric 433, "#{raw_args[1]} :Nickname is already in use."
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
					
				when 'oper'
					name = raw_args[1].downcase
					pass = raw_args[2]
					
					Config.opers.each do |oper|
						if oper['login'].downcase == name and oper['pass'] == pass
							@opered = true
						end
					end
					put_snumeric 381, ':You have entered... the Twilight Zone!' if @opered
					put_snumeric 491, ':Only few of mere mortals may try to enter the twilight zone' unless @opered
					
				when 'kill'
					if @opered
						target = $server.find_nick(raw_args[1])
						if target == nil
							put_snumeric 401, raw_args[1] + ' :No such nick/channel'
						else
							target.kill self, "Killed (#{@nick} ())"
						end
					else
						put_snumeric 481, ':Permission Denied- You do not have the correct IRC operator privileges'
					end
					
				when 'whois'
					target = $server.find_nick(raw_args[1])
					if target == nil
						put_snumeric 401, raw_args[1] + ' :No such nick/channel'
					else
						put_snumeric 311, "#{target.nick} #{target.ident} #{target.host} * :#{target.realname}"
						put_snumeric 378, "#{target.nick} :is connecting from *@#{target.addr[2]} #{target.ip}"
						put_snumeric 312, "#{target.nick} #{$server.name} :#{Config.server_desc}"
						put_snumeric 317, "#{target.nick} 2 1233972544 :seconds idle, signon time"
						put_snumeric 318, "#{target.nick} :End of /WHOIS list."
					end
					
				when 'version'
					send_version true # detailed
				when 'lusers'
					send_lusers
				when 'motd'
					send_motd
					
				when 'privmsg', 'notice'
					target = $server.find_channel(raw_args[1])
					if target == nil
						target = $server.find_nick(raw_args[1])
						if target == nil
							put_snumeric 401, raw_args[1] + ' :No such nick/channel'
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
					join channel
					
				when 'part'
					channel = $server.find_channel(raw_args[1])
					if channel == nil
						put_snumeric 403, raw_args[1] + ' :No such channel'
					elsif !(channel.users.include?(self))
						put_snumeric 403, raw_args[1] + ' :No such channel'
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
					close 'Leaving'
					return
			
				when 'pong'
				when 'ping'
					target = raw_args[1]
					puts ":#{$server.name} PONG #{$server.name} :#{target}"
					
				when 'userhost'
					target = $server.find_nick(raw_args[1])
					if target == nil
						put_snumeric 401, raw_args[1] + ' :No such nick/channel'
					else
						put_snumeric 302, ":#{target.nick}=+#{target.ident}@#{target.ip}"
					end
					
				else
					put_snumeric 421, command + ' :Unknown command'
			end
		end
  end
end

class Config
	def self.load(filename)
		@yaml = YAML.load(File.open(filename))
	end
	
	# Shorter way to access data
	def self.method_missing(m, *args, &blck)
		raise ArgumentError, "wrong number of arguments (#{args.length} for 0)" if args.length > 0
		raise NoMethodError, "undefined method '#{m}' for #{self}" unless @yaml.has_key?(m.to_s.gsub('_', '-'))
		@yaml[m.to_s.gsub('_', '-')]
	end
end

# Load the config
Config.load('rbircd.conf')

# Daemons.daemonize
$server = IRCServer.new(Config.listen_port.to_i, Config.listen_host)
$server.name = Config.server_name

$server.audit = true
$server.debug = true
begin
	$server.start
	loop do
		sleep 60 
		$server.clients.each do |value|
			begin
				value.puts 'PING :' + $server.name
			rescue => detail
				value.close
				$server.clients.delete(value)
			end	
		end
	end

ensure
	$server.clients.each do |value|
		begin
			value.skill 'Server is going down NOW!'
		rescue => detail
			$server.clients.clear
		end	
	end
end
