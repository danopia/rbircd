# Copyright (c) 2009 Daniel Danopia
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of Danopia nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

class IRCClient
  attr_reader :nick, :ident, :realname, :io, :addr, :ip, :host, :dead, :umodes
  attr_accessor :opered, :away, :created_at, :modified_at
  
	def initialize(io)
		@nick = '*'
		@ident = nil
		@realname = nil
		@io = io
		@dead = false
		@opered = false
		@umodes = ''
		@away = nil
		@created_at = Time.now
		@modified_at = Time.now
		
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
		$server.clients.each do |client|
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
		puts(":#{$server.name} KILL #{@nick} :#{$server.name} #{reason}")
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
		put_snumeric '005', "NAMESX SAFELIST HCN MAXCHANNELS=#{ServerConfig.max_channels} CHANLIMIT=#:#{ServerConfig.max_channels_per_user} MAXLIST=b:60,e:60,I:60 NICKLEN=#{ServerConfig.max_nick_length} CHANNELLEN=#{ServerConfig.max_channel_length} TOPICLEN=#{ServerConfig.max_topic_length} KICKLEN=#{ServerConfig.max_kick_length} AWAYLEN=#{ServerConfig.max_away_length} MAXTARGETS=#{ServerConfig.max_targets} WALLCHOPS :are supported by this server"
		put_snumeric '005', "WATCH=128 SILENCE=15 MODES=12 CHANTYPES=# PREFIX=(qaohv)~&@%+ CHANMODES=beI,kfL,lj,psmntirRcOAQKVCuzNSMTG NETWORK=#{ServerConfig.network_name.gsub(' ', '-')} CASEMAPPING=ascii EXTBAN=~,cqnr ELIST=MNUCT STATUSMSG=~&@%+ EXCEPTS INVEX :are supported by this server"
		put_snumeric '005', 'CMDS=KNOCK,MAP,DCCALLOW,USERIP :are supported by this server'
	end
	
	def send_lusers
		opers = $server.clients.select{|user|user.opered}.size
		invisible = $server.clients.select{|user|user.has_umode?('i')}.size
		total = $server.clients.size
		put_snumeric 251, ":There are #{total - invisible} users and #{invisible} invisible on 1 servers"
		put_snumeric 252, "#{opers} :operator(s) online"
		put_snumeric 254, "#{$server.channels.size} :channels formed"
		put_snumeric 255, ":I have #{total} clients and 0 servers"
		put_snumeric 265, ":Current Local Users: #{total}  Max: #{total}"
		put_snumeric 266, ":Current Global Users: #{total}  Max: #{total}"
	end

	def get_motd
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
				put_snumeric 372, ":- #{line}"
			end
			put_snumeric 376, ':End of /MOTD command.'
		else
			put_snumeric 422, ':MOTD File is missing'
		end
	end
	
	def join(channel)
		channel = IRCChannel.find_or_create(channel) unless channel.is_a?(IRCChannel)
		return(channel) if channel.users.include?(self)
		channel.users << self
		channel.users.each do |user|
			user.puts ":#{path} JOIN :#{channel.name}"
		end
		send_topic(channel)
		send_names(channel)
	end
	
	def send_topic(channel, detailed=false)
		if not channel.topic
			put_snumeric 331, "#{channel.name} :No topic is set." if detailed
			return
		end
		put_snumeric 332, "#{channel.name} :#{channel.topic}"
		put_snumeric 333, "#{channel.name} #{channel.topic_author} #{channel.topic_timestamp.to_i}"
	end
	def send_names(channel)
		nicks = channel.users.map do |user|
			user.prefix_for(channel) + user.nick
		end
		put_snumeric 353, "= #{channel.name} :#{nicks.join(' ')}"
		put_snumeric 366, "#{channel.name} :End of /NAMES list."
	end
	def send_modes(channel, detailed=false)
		put_snumeric 324, "#{channel.name} +#{channel.modes}"
		put_snumeric 329, "#{channel.name} #{channel.mode_timestamp.to_i}"
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
			puts ":#{path} NICK :#{newnick}"
			
			updated_users = [self]
			self.channels do |channel| # Loop through the channels I'm in
				channel.users.each do |user| # ...and then each user in each channel
					unless updated_users.include?(user)
						user.puts ":#{path} NICK :#{newnick}"
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
  	@modified_at = Time.now
  	
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
				
			when 'away'
				if args.size == 1
					@away = nil
					put_snumeric 305, ':You are no longer marked as being away'
				else
					@away = args[1]
					put_snumeric 306, ':You have been marked as being away'
				end
				
			when 'oper'
				name = args[1].downcase
				pass = args[2]
				
				ServerConfig.opers.each do |oper|
					if oper['login'].downcase == name && oper['pass'] == pass
						@opered = true
						break
					end
				end
				if @opered
					put_snumeric 381, ':You have entered... the Twilight Zone!'
					join ServerConfig.oper_channel if ServerConfig.oper_channel
				else
					put_snumeric 491, ':Only few of mere mortals may try to enter the twilight zone'
				end
				
			when 'kill'
				if args.size < 3
					put_snumeric 461, 'KILL :Not enough parameters'
				elsif @opered
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
					end unless @opered
					channels &= my_channels if target.umodes.include?('p')
					channel_strs = []
					channels.each do |channel|
						channel_strs << target.prefix_for(channel) + channel.name
					end
					put_snumeric 319, "#{target.nick} :#{channel_strs.join(' ')}" unless channel_strs.empty?
					
					put_snumeric 301, "#{target.nick} :#{target.away}" if target.away
					put_snumeric 312, "#{target.nick} #{$server.name} :#{ServerConfig.server_desc}"
					put_snumeric 317, "#{target.nick} #{Time.now.to_i - @modified_at.to_i} #{@created_at.to_i} :seconds idle, signon time"
					put_snumeric 318, "#{target.nick} :End of /WHOIS list."
				end
				
			when 'list'
				put_snumeric 321, 'Channel :Users  Name'
				pattern = nil
				not_pattern = nil
				min = nil
				max = nil
				if args[1]
					args[1].split(',').each do |arg|
						if arg =~ /<([0-9]+)/
							max = $1.to_i
						elsif arg =~ />([0-9]+)/
							min = $1.to_i
						elsif arg[0,1] == '!'
							not_pattern = Regexp::escape(args[1][1..-1]).gsub('\*','.*').gsub('\?', '.')
							not_pattern = /^#{not_pattern}$/i
						else
							pattern = Regexp::escape(args[1]).gsub('\*','.*').gsub('\?', '.')
							pattern = /^#{pattern}$/i
						end
					end
				end
				
				my_channels = self.channels
				$server.channels.each do |channel|
					next if channel.has_any_mode?('ps') && !my_channels.include?(channel) && !@opered
					next if pattern && !(channel.name =~ pattern)
					next if not_pattern && channel.name =~ not_pattern
					next if min && !(channel.users.size > min)
					next if max && !(channel.users.size < max)
					topic = ' ' + (channel.topic || '')
					topic = "[+#{channel.modes}] #{topic}" if channel.modes
					put_snumeric 322, "#{channel.name} #{channel.users.size} :#{topic}"
				end
				put_snumeric 323, ':End of /LIST'
				
			when 'who'
				channel = nil
				users = []
				if args[1]
					channel = IRCChannel.find(args[1])
					users = channel.users if channel
				else
					users = $server.clients
				end
				channel_name = channel && channel.name
				users.each do |user|
					# Phew.
					next if user.has_umode?('i') && !(@opered || user == self || !(user.channels & self.channels).empty?)
					
					this_channel = channel_name
					this_channel ||= user.channels[0].name if user.channels[0]
					this_channel ||= '*'
					
					prefix = 'G' if user.away
					prefix ||= 'H'
					prefix += user.prefix_for(channel || user.channels[0]) if channel || user.channels[0]
					prefix += 'B' if user.has_umode?('B')
					prefix += 'r' if user.has_umode?('r')
					prefix += '*' if user.opered && (!user.has_umode?('H') || @opered)
					prefix += '!' if user.has_umode?('H') && @opered
					prefix += '?' if user.has_umode?('i')
					
					put_snumeric 352, "#{this_channel} #{user.nick} #{user.host} #{$server.name} #{user.ident} #{prefix} :0 #{user.realname}"
				end
				put_snumeric 315, "#{(args[1] || '*')} :End of /WHO list."
			
			when 'version'
				send_version true # detailed
				
			when 'lusers'
				send_lusers
				
			when 'motd'
				send_motd
				
			when 'privmsg'
				target = IRCChannel.find(args[1])
				if target == nil
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, "#{args[1]} :No such nick/channel"
					else
						target.puts ":#{path} PRIVMSG #{target.nick} :#{args[2]}"
					end
				else
					target.message self, args[2]
				end
				
			when 'notice'
				target = IRCChannel.find(args[1])
				if target == nil
					target = IRCClient.find(args[1])
					if target == nil
						put_snumeric 401, "#{args[1]} :No such nick/channel"
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
					join args[1]
				end
				
			when 'part'
				channel = IRCChannel.find(args[1])
				if channel == nil
					put_snumeric 403, args[1] + ' :No such channel'
				elsif !(channel.users.include?(self))
					put_snumeric 403, args[1] + ' :No such channel'
				else
					part channel, args[2] || 'Leaving'
				end
				
			when 'kick'
				if args.size < 3
					put_snumeric 461, 'KICK :Not enough parameters'
					return
				end
				
				channel = IRCChannel.find(args[1])
				target = IRCClient.find(args[2])
				
				if channel == nil
					put_snumeric 403, args[1] + ' :No such channel'
				elsif target == nil
					put_snumeric 501, args[2] + ' :No such nick/channel'
				elsif !target.is_on(channel)
					put_snumeric 482, "#{target.nick} #{channel.name} :They aren\'t on that channel"
				elsif !is_op_on(channel)
					put_snumeric 482, channel.name + ' :You\'re not channel operator'
				else
					target.kicked_from(channel, self, args[3] || @nick)
				end
				
			when 'names'
				channel = IRCChannel.find(args[1])
				send_names(channel)
				
			when 'topic'
				channel = IRCChannel.find(args[1])
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
				target = IRCChannel.find(args[1])
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
  	puts ":#{path} MODE #{@nick} :#{str}" if str && str.size > 0
  	str
  end
  def change_chmode(channel, changes_str, params=[])
		#<< MODE ##meep b
		#>> :Silicon.EighthBit.net 367 danopia ##meep danopia!*@* danopia 1247529868
		#>> :Silicon.EighthBit.net 368 danopia ##meep :End of Channel Ban List
		#<< MODE ##meep I
		#>> :Silicon.EighthBit.net 346 danopia ##meep danopia!*@* danopia 1247529861
		#>> :Silicon.EighthBit.net 347 danopia ##meep :End of Channel Invite List
		#<< MODE ##meep e
		#>> :Silicon.EighthBit.net 348 danopia ##meep danopia!*@* danopia 1247529865
		#>> :Silicon.EighthBit.net 349 danopia ##meep :End of Channel Exception List
		
		#>> :hubbard.freenode.net 482 danopia` ##GPT :You need to be a channel operator to do that
  	valid = 'vhoaqbceIfijklmnprstzACGMKLNOQRSTVu'.split('')
  	listsA = 'vhoaq'.split('')
  	listsB = 'beI'.split('')
  	need_params = 'vhoaqbeIfjklL'.split('')
  	str = parse_mode_string(changes_str, params) do |add, char, param|
  		next false unless valid.include? char
  		next :need_param if need_params.include?(char) && !param
  		if listsA.include? char
				list = nil
				
				case char
					when 'q'; list = channel.owners; param = IRCClient.find(param)
					when 'a'; list = channel.protecteds; param = IRCClient.find(param)
					when 'o'; list = channel.ops; param = IRCClient.find(param)
					when 'h'; list = channel.halfops; param = IRCClient.find(param)
					when 'v'; list = channel.voices; param = IRCClient.find(param)
					
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
			elsif listsB.include? char
				list = nil
				to_set = nil
				
				case char
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
  		elsif add
				channel.modes << char
			else
				channel.modes = channel.modes.delete char
  		end
  		true
  	end
  	channel.send_to_all ":#{path} MODE #{channel.name} :#{str}" if str && str.size > 0
  	str
  end
  
  def parse_mode_string(mode_str, params=[])
  	add = true
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
  				ret = yield(add, mode_chr, params.shift || :none)
  			end
  			if !ret || ret == :need_param
				elsif add
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
  
  def is_on(channel)
  	channel.users.include? self
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
  
  def is_voice_or_better_on(channel)
  	is_voice_on(channel) || is_halfop_or_better_on(channel)
  end
  def is_halfop_or_better_on(channel)
  	is_halfop_on(channel)|| is_op_or_better_on(channel)
  end
  def is_op_or_better_on(channel)
  	is_op_on(channel)  || is_protected_or_better_on(channel)
  end
  def is_protected_or_better_on(channel)
  	is_protected_on(channel) || is_owner_on(channel)
  end
  def is_owner_or_better_on(channel)
  	is_owner_on(channel)
  end
	
	def has_umode?(umode)
		@umodes.include? umode
	end
	def has_any_umode?(umodes)
		umodes.split('').each do |umode|
			return true if has_umode?(umode)
		end
		false
	end
  
end
