#!/usr/bin/env ruby

# Thanks to Tsion for the Server class

require 'socket'
require 'yaml'
require 'rubygems'
require 'daemons'

class IRCServer
  attr_accessor :debug, :clients, :channels, :name, :maxConnections, :listeners, :listen_socks, :socks, :running
  
	def initialize(name=nil)
    @debug = true
    @clients = []
    @channels = []
    @name = name
    @maxConnections = maxConnections
    @listeners = []
    @listen_socks = []
		@socks = []
		@running = false
	end
	
	def add_listener(host=nil, port=6667)
		@listeners << [host || '0.0.0.0', port]
		@listen_socks << TCPServer.new(host || '0.0.0.0', port) if @running
	end
	
  def log(msg)
    puts "[#{Time.new.ctime}] %s" % msg
  end
  def log_nick(nick, msg)
    log "#{@host}:#{@port} #{nick}\t%s" % msg
  end
	
	def run
		begin
			if @listeners.empty?
				log 'No listeners defined!'
				return false
			end
			
			# Create TCPServers for each listener
			@listen_socks.clear
			@listeners.each do |listener|
				@listen_socks << TCPServer.new(listener[0], listener[1])
			end
			
			@running = true
			log("Server started with #{@listen_socks.size} listener" +
				(@listen_socks.size == 1 ? '' : 's'))

			#BasicSocket.do_not_reverse_lookup = true

			loop do
				active = nil
				remove_closed
				begin
					active = select(@listen_socks + @socks)[0][0]
				rescue IOError
					next # next time will remove closed sockets again
				end
				next if not active
				
				if @listen_socks.include? active
					new_sock = active.accept
					new_client = IRCClient.new new_sock
					log "connected: #{new_client.ip}" if @debug
					@socks << new_sock
					@clients << new_client
				else
					if active.eof?
						active.client.skill
						@clients.delete(active.client)
						@socks.delete(active)
						log "disconnected: #{active.client.ip}" if @debug
						active.close
						next
					end
					line = active.gets
					if line == '' or line == nil
						log 'FAILURE'
					else
						begin
							active.client.handle_packet line
						rescue => error
							log error.to_s
							active.client.skill 'Error occured'
							@clients.delete(active.client)
							@socks.delete(active)
							log "disconnected due to error: #{active.client.ip}"
						end
					end
				end
			end
		
		rescue => error
			log error.to_s
			@socks.each do |sock|
				sock.client.skill 'Server is going down NOW!'
			end
			@socks.clear
			@listen_socks.each do |listener|
				listener.close
			end
			@listen_socks.clear
			@running = false
			error.throw
		end
	end
	
	def remove_closed
		@socks.reject! do |sock|
			sock.closed? #|| sock.eof?
		end
	end
	
	def remove_client(client)
		remove_sock client.io
	end
	def remove_sock(sock)
		@socks.delete sock
		@clients.delete sock.client
	end
end

class IRCChannel
	attr_reader :name, :users
	attr_reader :owners, :protecteds, :ops, :halfops, :voices
	attr_reader :bans, :invex, :excepts
	attr_accessor :modes, :mode_timestamp
	attr_reader :topic, :topic_timestamp
	attr_accessor :topic_author
	
	def initialize(name)
		@name = name
		@users = []
		
		@owners = []
		@protecteds = []
		@ops = []
		@halfops = []
		@voices = []
		
		@bans = []
		@invex = []
		@excepts = []
		
		@modes = 'ns'
		@mode_timestamp = Time.now.gmtime.to_i
		
		@topic = nil
		@topic_author = nil
		@topic_timestamp = nil
	end

	def self.find(name)
		name = name.downcase
		@channels.each do |channel|
			return channel if channel.name.downcase == name
		end
		nil
	end

	def self.find_or_create(name)
		channel = IRCChannel.find name
		return channel if channel
		
		channel = IRCChannel.new(name)
		$server.channels << channel
		channel
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
	
	def message(sender, message)
		send_to_all_except sender, ":#{sender.path} PRIVMSG #{name} :#{message}"
	end
	def notice(sender, message)
		send_to_all_except sender, ":#{sender.path} NOTICE #{name} :#{message}"
	end
	
	def part(client, message='Leaving')
		send_to_all ":#{client.path} PART #{name} :#{message}"
		remove client
	end
	
	def remove(client)
		@users.delete(client)
		
		@owners.delete(client)
		@protecteds.delete(client)
		@ops.delete(client)
		@halfops.delete(client)
		@voices.delete(client)
		
		destroy('Channel empty') if empty?
	end
	
	def empty?
		@users.empty?
	end
	
	def destroy(reason='OM NOM NOM')
		@users.each do |user|
			user.kicked_from self, $server.name, reason
		end
		$server.channels.delete self
	end
	
	def has_mode?(mode)
		@modes.include? mode
	end
	def has_any_mode?(modes)
		modes.split('').each do |mode|
			return true if has_mode?(mode)
		end
		false
	end
end

class IRCClient
  attr_reader :nick, :ident, :realname, :io, :addr, :ip, :host, :dead, :umodes
  attr_accessor :opered
  
	def initialize(io)
		@nick = '*'
		@ident = nil
		@realname = nil
		@io = io
		@dead = false
		@opered = false
		@umodes = ''
		
		@addr = io.peeraddr
    @ip = @addr[3]
		@host = @addr[2]
		
		io.instance_variable_set('@client', self)
		def io.client
			@client
		end
		
    puts ":#{$server.name} NOTICE AUTH :*** Looking up your hostname..."
    puts ":#{$server.name} NOTICE AUTH :*** Found your hostname"
	end
	
	def self.find(nick)
		nick = nick.downcase
		@clients.each do |client|
			return client if client.nick.downcase == nick
		end
		nil
	end

	def is_registered?
		@nick != '*' and @ident != nil
	end
	def check_registration()
		send_welcome_flood if is_registered?
		change_umode '+iwx'
		#puts ":#{@nick} MODE #{@nick} :+iwx"
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
		
		$server.remove_sock io
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
		put_snumeric '001', ":Welcome to the #{ServerConfig.network_name} IRC Network #{path}"
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
		put_snumeric '005', "WATCH=128 SILENCE=15 MODES=12 CHANTYPES=# PREFIX=(qaohv)~&@%+ CHANMODES=beI,kfL,lj,psmntirRcOAQKVCuzNSMTG NETWORK=#{ServerConfig.network_name.gsub(' ', '-')} CASEMAPPING=ascii EXTBAN=~,cqnr ELIST=MNUCT STATUSMSG=~&@%+ EXCEPTS INVEX :are supported by this server"
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
			filename = ServerConfig.motd_file
			return File.new(filename).read
		rescue
		end
		
		begin
			program = ServerConfig.motd_program
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
		channel = Channel.find_or_create(channel) unless channel.is_a?(IRCChannel)
		return(channel) if channel.users.include?(self)
		channel.users << self
		channel.users.each do |user|
			user.puts ":#{path} JOIN :#{channel.name}"
		end
		send_topic(channel)
		send_names(channel)
		#>> :Silicon.EighthBit.net 352 danopia #bitcast danopia danopia::EighthBit::staff Silicon.EighthBit.net danopia Hr* :0 Daniel Danopia
		#>> :Silicon.EighthBit.net 352 danopia #bitcast nixeagle 9F3ADEED.AC9A3767.180762F4.IP Silicon.EighthBit.net nixeagle Gr* :0 James
		#>> :Silicon.EighthBit.net 352 danopia #bitcast CodeBlock CodeBlock::EighthBit::staff Platinum.EighthBit.net CodeBlock Hr*@ :1 CodeBlock
	end
	def send_topic(channel, detailed=false)
		if not channel.topic
			put_snumeric 331, channel.name + ' :No topic is set.' if detailed
			return
		end
		put_snumeric 332, channel.name + ' :' + channel.topic
		put_snumeric 333, "#{channel.name} #{channel.topic_author} 1247378633"
	end
	def send_names(channel)
		nicks = channel.users.map do |user|
			user.prefix_for(channel) + user.nick
		end
		put_snumeric 353, "= #{channel.name} :#{nicks.join(' ')}"
		put_snumeric 366, channel.name + ' :End of /NAMES list.'
	end
	#>> :Silicon.EighthBit.net 324 danopia #bitcast +nt 
	#>> :Silicon.EighthBit.net 329 danopia #bitcast 1247378376
	def send_modes(channel, detailed=false)
		put_snumeric 324, channel.name + ' +' + channel.modes
	end
	
	def part(channel, reason = 'Leaving')
		channel.part self, reason
	end
	
	def kicked_from(channel, kicker, reason = nil)
		kicker = kicker.path if kicker.is_a?(IRCClient)
		reason = ' :' + reason if reason
		channel.send_to_all ":#{kicker} KICK #{channel.name} #{@nick}#{reason}"
		channel.remove(self)
	end
	
	def prefix_for(channel, whois=false)
		prefix = ''
		prefix << '~' if channel.owners.include?(self)
		prefix << '&' if channel.protecteds.include?(self)
		prefix << '@' if channel.ops.include?(self)
		prefix << '%' if channel.halfops.include?(self)
		prefix << '+' if channel.voices.include?(self)
		prefix
	end
	
	def nick=(newnick)
		if is_registered?
			puts ":#{path} NICK :" + newnick
			
			updated_users = [self]
			self.channels do |channel| # Loop through the channels I'm in
				channel.users.each do |user| # ...and then each user in each channel
					unless updated_users.include?(user)
						user.puts ":#{path} NICK :" + newnick
						updated_users << user
					end
				end
			end
			
			@nick = newnick # Changed last so that the path is right ^^
		else
			@nick = newnick # Changed first so check_registration can see it
			check_registration
		end
	end
	
	def channels
		$server.channels.select do |channel|
			channel.users.include?(self)
		end
	end
	
  def handle_packet(line)
		# Parse as per the RFC
		raw_parts = line.chomp.split(' :', 2)
		args = raw_parts[0].split(' ')
		args << raw_parts[1] if raw_parts.size > 1
		
		command = args[0].downcase
		$server.log_nick(@nick, command)
		case command
		
			when 'user'
				if args.size < 5
					put_snumeric 461, 'USER :Not enough parameters'
				elsif is_registered?
					put_snumeric 462, ':You may not reregister'
				else
					@ident = args[1]
					@realname = args[4]
					check_registration
				end
		
			when 'nick'
				if args.size < 2 || args[1].size < 1
					put_snumeric 431, ':No nickname given'
				elsif !(args[1] =~ /^[a-zA-Z\[\]_|`^][a-zA-Z0-9\[\]_|`^]{0,29}$/)
					put_snumeric 432, "#{args[1]} :Erroneous Nickname: Illegal characters"
				elsif IRCClient.find(args[1])
					put_snumeric 433, "#{args[1]} :Nickname is already in use."
				else
					self.nick = args[1]
				end
				
			when 'oper'
				name = args[1].downcase
				pass = args[2]
				
				ServerConfig.opers.each do |oper|
					if oper['login'].downcase == name and oper['pass'] == pass
						@opered = true
						break
					end
				end
				if @opered
					put_snumeric 381, ':You have entered... the Twilight Zone!'
					join ServerConfig.oper_channel
				else
					put_snumeric 491, ':Only few of mere mortals may try to enter the twilight zone'
				end
				
			when 'kill'
				if @opered
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, args[1] + ' :No such nick/channel'
					else
						target.kill self, "Killed (#{@nick} (#{args[2]}))"
					end
				else
					put_snumeric 481, ':Permission Denied- You do not have the correct IRC operator privileges'
				end
				
			when 'whois'
				target = IRCClient.find(args[1])
				if target == nil
					put_snumeric 401, args[1] + ' :No such nick/channel'
				else
					put_snumeric 311, "#{target.nick} #{target.ident} #{target.host} * :#{target.realname}"
					put_snumeric 378, "#{target.nick} :is connecting from *@#{target.addr[2]} #{target.ip}"
					put_snumeric 379, "#{target.nick} :is using modes +#{target.umodes}" if target == self || @opered
					
					channels = target.channels
					my_channels = self.channels
					channels.reject! do |channel|
						channel.has_any_mode?('ps') && !my_channels.include?(channel)
					end
					channels &= my_channels if target.umodes.include?('p')
					channel_strs = []
					channels.each do |channel|
						channel_strs << target.prefix_for(channel) + channel.name
					end
					put_snumeric 319, "#{target.nick} :#{channel_strs.join(' ')}" unless  channel_strs.empty?
					
					put_snumeric 312, "#{target.nick} #{$server.name} :#{ServerConfig.server_desc}"
					put_snumeric 317, "#{target.nick} 2 1233972544 :seconds idle, signon time"
					put_snumeric 318, "#{target.nick} :End of /WHOIS list."
				end
				
			when 'version'
				send_version true # detailed
			when 'lusers'
				send_lusers
			when 'motd'
				send_motd
				
			when 'privmsg'
				target = Channel.find(args[1])
				if target == nil
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, args[1] + ' :No such nick/channel'
					else
						target.puts ":#{path} PRIVMSG #{target.nick} :#{args[2]}"
					end
				else
					target.message self, args[2]
				end
				
			when 'notice'
				target = Channel.find(args[1])
				if target == nil
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, args[1] + ' :No such nick/channel'
					else
						target.puts ":#{path} NOTICE #{target.nick} :#{args[2]}"
					end
				else
					target.notice self, args[2]
				end
				
			when 'join'
				if args.size < 2 || args[1].size < 1
					put_snumeric 461, 'JOIN :Not enough parameters'
				elsif !(args[1] =~ /^\#[a-zA-Z0-9`~!@\#$%^&*\(\)\'";|}{\]\[.<>?]{0,29}$/)
					put_snumeric 432, "#{args[1]} :No such channel"
				else
					join channel
				end
				
			when 'part'
				channel = Channel.find(args[1])
				if channel == nil
					put_snumeric 403, args[1] + ' :No such channel'
				elsif !(channel.users.include?(self))
					put_snumeric 403, args[1] + ' :No such channel'
				else
					part channel, args[2] || 'Leaving'
				end
				
			when 'names'
				channel = Channel.find(args[1])
				send_names(channel)
				
			when 'topic'
				channel = Channel.find(args[1])
				if args.size == 2
					send_topic(channel, true) # Detailed (send no-topic-set if no topic)
				else
					channel.topic = args[2]
					channel.topic_author = @nick
					channel.send_to_all ":#{path} TOPIC #{channel.name} :#{args[2]}"
				end
				
			when 'mode'
				# :Silicon.EighthBit.net 482 danopia #offtopic :You're not channel operator
				# :Silicon.EighthBit.net 008 danopia :Server notice mask (+kcfvGqso)
				target = Channel.find(args[1])
				if target == nil
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, args[1] + ' :No such nick/channel'
					else
						return unless target == self
						if args.size == 2
							put_snumeric 221, '+' + self.umodes
						else
							change_umode(args[2], args[3..-1])
						end
					end
				else
					if args.size == 2
						send_modes target
					else
						change_chmode target, args[2], args[3..-1]
					end
				end
				
			when 'quit'
				close args[1] || 'Client quit'
				return
		
			when 'pong'
			when 'ping'
				target = args[1]
				puts ":#{$server.name} PONG #{$server.name} :#{target}"
				
			when 'userhost'
				target = IRCClient.find(args[1])
				if target == nil
					put_snumeric 401, args[1] + ' :No such nick/channel'
				else
					put_snumeric 302, ":#{target.nick}=+#{target.ident}@#{target.ip}"
				end
				
			else
				put_snumeric 421, command + ' :Unknown command'
		end
  end
  
  def change_umode(changes_str, params=[])
  	valid = 'oOaANCdghipqrstvwxzBGHRSTVW'.split('')
  	str = parse_mode_string(changes_str, params) do |add, char, param|
  		next false unless valid.include? char
  		if @umodes.include?(char) ^ !add
  			# Already set
   			next false
  		elsif add
				@umodes << char
			else
				@umodes = @umodes.delete char
  		end
  		true
  	end
  	puts ":#{path} MODE #{@nick} :#{str}"
  	str
  end
  def change_chmode(channel, changes_str, params=[])
  	valid = 'vhoaqbceIfijklmnprstzACGMKLNOQRSTVu'.split('')
  	lists = 'vhoaqbeI'.split('')
  	need_params = 'vhoaqbeIfjklL'.split('')
  	str = parse_mode_string(changes_str, params) do |add, char, param|
  		next false unless valid.include? char
  		next :need_param if need_params.include?(char) && !param
  		if lists.include? char
				list = nil
				to_set = nil
				to_set = nil
				case char
					when 'q'; list = channel.owners
					when 'a'; list = channel.protecteds
					when 'o'; list = channel.ops
					when 'h'; list = channel.halfops
					when 'v'; list = channel.voices
					
					when 'b'; list = channel.bans
					when 'e'; list = channel.excepts
					when 'I'; list = channel.invex
				end
				next false if list.include?(param) ^ !add
				if add
					list << param
				else
					list.delete param
				end
  		elsif channel.modes.include?(char) ^ !add
  			# Already set
   			next false
  		elsif add || add == nil
				channel.modes << char
			else
				channel.modes = channel.modes.delete char
  		end
  		true
  	end
  	channel.send_to_all ":#{path} MODE #{channel.name} :#{str}"
  	str
  end
  
  def parse_mode_string(mode_str, params=[])
  	add = nil
  	additions = []
  	deletions = []
  	new_params = []
  	mode_str.split('').each do |mode_chr|
  		if mode_chr == '+'
  			add = true
  		elsif mode_chr == '-'
  			add = false
  		else
  			ret = yield(add, mode_chr, nil)
  			if ret == :need_param && params[0]
  				new_params << params[0]
  				ret = yield(add, mode_chr, params.shift)
  			end
  			if !ret || ret == :need_param
				elsif add || add == nil
					if deletions.include?(mode_chr)
						deletions.delete(mode_chr)
					else
						additions << mode_chr unless additions.include?(mode_chr)
					end
				else
					if additions.include?(mode_chr)
						additions.delete(mode_chr)
					else
						deletions << mode_chr unless deletions.include?(mode_chr)
					end
				end
  		end
  	end
  	new_str = ''
  	new_str << '+' + additions.join('') unless additions.empty?
  	new_str << '-' + deletions.join('') unless deletions.empty?
  	new_str << ' ' + new_params.join(' ') unless new_params.empty?
  	new_str
  end
  
  def is_voice_on(channel)
  	channel.voices.include? self
  end
  def is_halfop_on(channel)
  	channel.halfops.include? self
  end
  def is_op_on(channel)
  	channel.ops.include? self
  end
  def is_protected_on(channel)
  	channel.protecteds.include? self
  end
  def is_owner_on(channel)
  	channel.owners.include? self
  end
  
end

class ServerConfig
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
ServerConfig.load('rbircd.conf')

# Daemons.daemonize
$server = IRCServer.new(ServerConfig.server_name)
$server.add_listener ServerConfig.listen_host, ServerConfig.listen_port.to_i

$server.debug = true

$server.run
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
