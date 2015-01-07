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

require 'lineconnection'

class IRCClient < LineConnection
  attr_accessor :server

  def initialize server
    super()

    @server = server
    @server.clients << self
		
		@nick = '*'
		@umodes = ''
		
		@protocols = []
		@watch = []
		@silence = []
		
		@created_at = Time.now
		@modified_at = Time.now
		
		@port, @ip = Socket.unpack_sockaddr_in get_peername
		@host = @ip
		
		send @server.name, :notice, 'AUTH', '*** Looking up your hostname...'
		send @server.name, :notice, 'AUTH', '*** Found your hostname'
  end

  def unbind
    super
    close 'Client disconnected'
    @server.remove_client self
  end


  attr_reader :nick, :ident, :realname, :conn, :addr, :ip, :host, :dead, :umodes, :server
  attr_accessor :opered, :away, :created_at, :modified_at

	def is_registered?
		@nick != '*' && @ident
	end
	def check_registration
		return unless is_registered?
		send_welcome_flood
		change_umode '+iwx'
	end
 
	def close reason='Client quit'
		@server.log_nick @nick, "User disconnected (#{reason})."
		return if @dead
		
		updated_users = [self]
		self.channels.each do |channel|
			channel.users.each do |user|
				next if updated_users.include? user
				user.send path, :quit, reason
				updated_users << user
			end
			channel.users.delete self
		end
		@dead = true
		
		send nil, :error, "Closing Link: #{@nick}[#{@ip}] (#{reason})"
		close_connection
	end
	
	def rawkill killer, message='Client quit'
		send killer, :kill, @nick, message
		close message
	end
	def kill killer, reason='Client quit'
		rawkill killer, "#{@server.name}!#{killer.host}!#{killer.nick} (#{reason})"
	end
	def skill reason='Client quit'
		rawkill @server.name, "#{@server.name} #{reason}"
	end
	
	def send from, *args
		args = args.clone # hopefully don't damage the passed array
		args.unshift args.shift.to_s.upcase
		args.unshift ":#{from}" if from
		args.push ":#{args.pop}" if args.last.to_s.include?(' ')
		
		send_line args.join(' ')
	end
	
	def send_numeric numeric, *args
		send @server.name, numeric, @nick, *args
	end
	
	def path
		"#{@nick}!#{@ident}@#{@host}"
	end
	
	def send_welcome_flood
		send_numeric '001', "Welcome to the #{ServerConfig.network_name} IRC Network #{path}"
		send_numeric '002', "Your host is #{@server.name}, running version RubyIRCd0.1.0"
		send_numeric '003', "This server was created Tue Dec 23 2008 at 15:18:59 EST"
		send_numeric '004', @server.name, 'RubyIRCd0.1.0', 'iowghraAsORTVSxNCWqBzvdHtGp', 'lvhopsmntikrRcaqOALQbSeIKVfMCuzNTGj'

		send_version
		send_lusers
		send_motd
	end
	
	def send_version(detailed=false)
		if detailed
			send_numeric 351, 'RubyIRCd0.1.0.', @server.name, 'FhiXeOoZE [Linux box 2.6.18-128.1.1.el5.028stab062.3 #1 SMP Sun May 10 18:54:51 MSD 2009 i686=2309]'
			send @server.name, :notice, @nick, 'OpenSSL 0.9.8k 25 Mar 2009'
			send @server.name, :notice, @nick, 'zlib 1.2.3'
			send @server.name, :notice, @nick, 'libcurl/7.19.4 GnuTLS/2.6.6 zlib/1.2.3 c-ares/1.6.0 libssh2/0.18'
		end
		
		features = ServerConfig.features.clone
		
		features.each_slice(13) do |slice| # Why 13? Ask freenode
			slice.map! do |(key, value)|
				(value == true) ? key.upcase : "#{key.upcase}=#{value}"
			end
			
			slice << 'are supported by this server'
			send_numeric '005', *slice
		end
	end
	
	def send_lusers
		opers = @server.clients.select {|user| user.opered }.size
		invisible = @server.clients.select {|user| user.has_umode?('i') }.size
		total = @server.clients.size
		
		send_numeric 251, "There are #{total - invisible} users and #{invisible} invisible on 1 servers"
		send_numeric 252, opers, 'operator(s) online'
		send_numeric 254, @server.channels.size, 'channels formed'
		send_numeric 255, "I have #{total} clients and 0 servers"
		send_numeric 265, "Current Local Users: #{total}  Max: #{total}"
		send_numeric 266, "Current Global Users: #{total}  Max: #{total}"
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
			send_numeric 375, "- #{@server.name} Message of the Day -"
			motd.each_line {|line| send_numeric 372, "- #{line}" }
			send_numeric 376, 'End of /MOTD command.'
		else
			send_numeric 422, 'MOTD File is missing'
		end
	end
	
	def join target
		channel = @server.find_channel target
		
		if !@server.validate_chan(target)
			send_numeric 432, target, 'No such channel'
		elsif channels.size >= ServerConfig.max_channels_per_user.to_i
			send_numeric 405, target, 'You have joined too many channels'
		elsif channel && channel.has_mode?('i')
			send_numeric 473, target, 'Cannot join channel (+i)'
		else
			channel ||= @server.find_or_create_channel(target)
			return channel if channel.users.include?(self)
			channel.join self
			send_topic channel
			send_names channel
		end
	end
	
	def send_topic channel, detailed=false
		if channel.topic
			send_numeric 332, channel.name, channel.topic
			send_numeric 333, channel.name, channel.topic_author, channel.topic_timestamp.to_i
		elsif detailed
			send_numeric 331, channel.name, 'No topic is set.'
		end
	end
	
	def send_names channel
		nicks = channel.users.map do |user|
			user.prefix_for(channel) + user.nick
		end
		send_numeric 353, '=', channel.name, nicks.join(' ')
		send_numeric 366, channel.name, 'End of /NAMES list.'
	end
	
	def send_modes channel, detailed=false
		send_numeric 324, channel.name, "+#{channel.modes}"
		send_numeric 329, channel.name, channel.mode_timestamp.to_i
	end
	
	def part channel, reason='Leaving'
		channel.part self, reason
	end
	
	def kicked_from channel, kicker, reason=nil
		channel.kick self, kicker, reason
	end
	
	def prefix_for channel, whois=false
		prefix = ''
		prefix << '~' if channel.owners.include? self
		prefix << '&' if channel.protecteds.include? self
		prefix << '@' if channel.ops.include? self
		prefix << '%' if channel.halfops.include? self
		prefix << '+' if channel.voices.include? self
		prefix
	end
	
	def nick=(newnick)
		if is_registered?
			send path, :nick, newnick
			
			updated_users = [self]
			self.channels.each do |channel| # Loop through the channels I'm in
				channel.users.each do |user| # ...and then each user in each channel
					unless updated_users.include?(user)
						user.send path, :nick, newnick
						updated_users << user
					end
				end
			end
			
			@server.users.delete @nick.downcase
			@server.users[newnick.downcase] = self
			
			@nick = newnick # Changed last so that the path is right
		else
			@nick = newnick # Changed first so check_registration can see it
			@server.users[@nick.downcase] = self
			
			check_registration
		end
	end
	
	def channels
		@server.channels.values.select do |channel|
			channel.users.include? self
		end
	end
	
  def receive_line line
		puts line if @server.debug
  	@modified_at = Time.now
  	
		# Parse as per the RFC
		raw_parts = line.chomp.split ' :', 2
		args = raw_parts.shift.split ' '
		args << raw_parts.first if raw_parts.any?
		
		command = args.shift.downcase
		@server.log_nick @nick, command
		
		if !is_registered? && !['user', 'nick', 'quit', 'pong'].include?(command)
			send_numeric 451, command.upcase, 'You have not registered'
			return
		end
		
		case command
		
			when 'user'
				if args.size < 4
					send_numeric 461, 'USER', 'Not enough parameters'
				elsif is_registered?
					send_numeric 462, 'You may not reregister'
				else
					@ident = args[0]
					@realname = args[3]
					check_registration
				end
		
			when 'nick'
				if args.empty? || args[0].size < 1
					send_numeric 431, 'No nickname given'
				elsif !@server.validate_nick(args[0])
					send_numeric 432, args[0], 'Erroneous Nickname: Illegal characters'
				elsif @server.find_user args[0]
					send_numeric 433, args[0], 'Nickname is already in use.'
				else
					self.nick = args[0]
				end
				
			when 'away'
				@away = args.first
				
				if args.empty?
					send_numeric 305, 'You are no longer marked as being away'
				else
					send_numeric 306, 'You have been marked as being away'
				end
				
			when 'oper'
				name = args.any? && args.shift.downcase
				pass = args.shift
				
				@oline = ServerConfig.opers.find do |oper|
					oper['login'].downcase == name && oper['pass'] == pass
				end
				
				if @oline
					@opered = true
					
					send_numeric 381, 'You have entered... the Twilight Zone!'
					join ServerConfig.oper_channel if ServerConfig.oper_channel
					
					#~ >> :jade.ninthbit.net 396 danopia netadmin.ninthbit.net :is now your displayed host
					#~ >> :jade.ninthbit.net MODE danopia :+o
					#~ >> :jade.ninthbit.net 381 danopia :You are now a NetAdmin
				else
					send_numeric 491, 'Only few of mere mortals may try to enter the twilight zone'
					# >> :jade.ninthbit.net 491 danopia :Invalid oper credentials
				end
				
			when 'kill'
				target = @server.find_user args[0]
				
				if args.size < 2
					send_numeric 461, 'KILL', 'Not enough parameters'
				elsif !@opered
					send_numeric 481, 'Permission Denied- You do not have the correct IRC operator privileges'
				elsif target
					target.kill self, "Killed (#{@nick} (#{args[1]}))"
				else
					send_numeric 401, args[0], 'No such nick/channel'
				end
				
			when 'whois'
				target = @server.find_user args[0]
				if !target
					send_numeric 401, args[0], 'No such nick/channel'
					return
				end
				
				#~ >> :anthony.freenode.net 671 danopia danopia :is using a secure connection
				#~ >> :anthony.freenode.net 330 danopia danopia danopia :is logged in as
				#~ >> :jade.ninthbit.net 335 danopia danopia :is a bot on NinthBit
				#~ >> :jade.ninthbit.net 313 danopia danopia :is a NetAdmin on NinthBit
				#~ >> :chat.combatcorps.com 313 danopia danopia :is a Network Administrator
				#~ >> :chat.combatcorps.com 310 danopia danopia :is available for help.
				
				send_numeric 311, target.nick, target.ident, target.host, '*', target.realname
				send_numeric 378, target.nick, "is connecting from *@#{target.ip} #{target.ip}"
				send_numeric 379, target.nick, "is using modes +#{target.umodes}" if target == self || @opered
				
				channels = target.channels
				my_channels = self.channels
				channels.reject! do |channel|
					channel.has_any_mode?('ps') && !my_channels.include?(channel)
				end unless @opered
				channels &= my_channels if target.umodes.include?('p')
				channels.map! do |channel|
					target.prefix_for(channel) + channel.name
				end
				send_numeric 319, target.nick, channels.join(' ') if channels.any?
				
				send_numeric 301, target.nick, target.away if target.away
				send_numeric 312, target.nick, @server.name, ServerConfig.server_desc
				send_numeric 317, target.nick, (Time.now.to_i - @modified_at.to_i), @created_at.to_i, 'seconds idle, signon time'
				send_numeric 318, target.nick, 'End of /WHOIS list.'
				
			when 'list'
				send_numeric 321, 'Channel', ':Users  Name'
				pattern = nil
				not_pattern = nil
				min = nil
				max = nil
				
				if args[0]
					args[0].split(',').each do |arg|
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
				@server.channels.each do |channel|
					next if channel.has_any_mode?('ps') && !my_channels.include?(channel) && !@opered
					next if pattern && !(channel.name =~ pattern)
					next if not_pattern && channel.name =~ not_pattern
					next if min && !(channel.users.size > min)
					next if max && !(channel.users.size < max)
					topic = ' ' + (channel.topic || '')
					topic = "[+#{channel.modes}] #{topic}" if channel.modes
					send_numeric 322, channel.name, channel.users.size, topic
				end
				send_numeric 323, 'End of /LIST'
				
			when 'who'
				channel = nil
				users = []
				
				if args.any?
					channel = @server.find_channel args[0]
					users = channel.users if channel
				else
					users = @server.clients
				end
				
				channel_name = channel && channel.name
				
				users.each do |user|
					# Phew.
					next if user.has_umode?('i') && !(@opered || user == self || !(user.channels & self.channels).empty?)
					
					this_channel = channel_name
					this_channel ||= user.channels[0].name if user.channels[0]
					this_channel ||= '*'
					
					prefix = user.away ? 'G' : 'H'
					prefix += user.prefix_for(channel || user.channels[0]) if channel || user.channels[0]
					prefix += 'B' if user.has_umode?('B')
					prefix += 'r' if user.has_umode?('r')
					prefix += '*' if user.opered && (!user.has_umode?('H') || @opered)
					prefix += '!' if user.has_umode?('H') && @opered
					prefix += '?' if user.has_umode?('i')
					
					send_numeric 352, this_channel, user.nick, user.host, @server.name, user.ident, prefix, "0 #{user.realname}"
				end
				send_numeric 315, (args[0] || '*'), 'End of /WHO list.'
			
			when 'version'
				send_version true # detailed
				
			when 'lusers'
				send_lusers
				
			when 'motd'
				send_motd
				
			when 'suicide'
				commit_suicide!
				
			when 'privmsg'
				target = @server.find_channel(args[0]) || @server.find_user(args[0])
				
				if target.is_a? IRCChannel
					target.message self, args[1]
				elsif target.is_a? IRCClient
					target.send path, :privmsg, target.nick, args[1]
				else
					send_numeric 401, args[0], 'No such nick/channel'
				end
				
			#~ when 'invite'
				#~ if args.size < 3
					#~ send_numeric 461, 'INVITE :Not enough parameters'.
				#~ else
					#~ user = @server.find_user args[1]
					#~ channel = @server.find_channel args[2]
					#~ 
					#~ if !target
						#~ send_numeric 401, "#{args[1]} :No such nick/channel"
					#~ elsif !channel
						#~ send_numeric 401, "#{args[1]} :No such nick/channel"
					#~ else
						#~ target.puts ":#{path} INVITE #{target.nick} :#{args[2]}"
					#~ end
				#~ end
				
			when 'notice'
				target = @server.find_channel(args[0]) || @server.find_user(args[0])
				
				if target.is_a? IRCChannel
					target.notice self, args[1]
				elsif target.is_a? IRCClient
					target.send path, :notice, target.nick, args[1]
				else
					send_numeric 401, args[0], 'No such nick/channel'
				end
				
			when 'join'
				if args.empty? || args[0].size < 1
					send_numeric 461, 'JOIN', 'Not enough parameters'
				else
					join args[0]
				end
				
			when 'part'
				channel = @server.find_channel args[0]
				if !channel
					send_numeric 403, args[0], 'No such channel'
				elsif channel.users.include? self
					part channel, args[1] || 'Leaving'
				else
					send_numeric 403, args[0], 'No such channel'
				end
				
			when 'reload'
				reload!
				
			when 'kick'
				if args.size < 2
					send_numeric 461, 'KICK', 'Not enough parameters'
					return
				end
				
				channel = @server.find_channel args[0]
				target = @server.find_user args[1]
				
				if !channel
					send_numeric 403, args[0], 'No such channel'
				elsif !target
					send_numeric 501, args[1], 'No such nick/channel'
				elsif !target.is_on(channel)
					send_numeric 482, target.nick, channel.name, "They aren't on that channel"
				elsif !is_op_on(channel)
					send_numeric 482, channel.name, "You're not channel operator"
				else
					target.kicked_from channel, self, args[2] || @nick
				end
				
			when 'names'
				channel = @server.find_channel args[0]
				send_names channel
				
			when 'topic'
				channel = @server.find_channel args[0]
				if args.size < 2
					send_topic channel, true # Detailed (send no-topic-set if no topic)
				elsif channel.has_mode?('t') && !is_op_or_better_on(channel)
					send_numeric 482, channel.name, "You're not channel operator"
				else
					channel.set_topic args[1], self
				end
				
			when 'mode'
				# :Silicon.EighthBit.net 482 danopia #offtopic :You're not channel operator
				# :Silicon.EighthBit.net 008 danopia :Server notice mask (+kcfvGqso)
				
				target = @server.find_channel(args[0]) || @server.find_user(args[0])
				
				if target.is_a? IRCChannel
					if args.size < 2
						send_modes target
					else
						change_chmode target, args[1], args[2..-1]
					end
				elsif target.is_a? IRCClient
					if args.size < 2
						send_numeric 221, '+' + self.umodes
					elsif target == self
						change_umode args[1], args[2..-1]
					else # someone else
					end
				else
					send_numeric 401, args[0], 'No such nick/channel'
				end
				
			when 'quit'
				close args[0] || 'Client quit'
		
			when 'pong' # do nothing
			when 'ping'
				send @server.name, :pong, @server.name, args[0]
				
			when 'userhost'
				target = @server.find_user args[0]
				if target
					send_numeric 302, "#{target.nick}=+#{target.ident}@#{target.ip}"
				else
					send_numeric 401, args[0], 'No such nick/channel'
				end
				
			else
				send_numeric 421, command.upcase, 'Unknown command'
		end
	
	rescue => ex
		puts ex.class, ex.message, ex.backtrace
		skill "Server-side #{ex.class}: #{ex.message}"
  end
  
  ########################################
  ########################################
  #### TODO: ANYTHING BELOW THIS LINE ####
  ########################################
  ########################################
  
  def change_umode(changes_str, params=[])
  	valid = 'oOaANCdghipqrstvwxzBGHRSTVW'
  	str = parse_mode_string(changes_str, valid) do |add, char|
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
  	send path, :mode, @nick, *str if str.any?
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
		
  	valid = 'vhoaqbceIfijklmnprstzACGMKLNOQRSTVu'
  	
  	str = parse_mode_string(changes_str, valid) do |add, char|
  	
  		if 'vhoaq'.include? char
				list = case char
					when 'q'; channel.owners
					when 'a'; channel.protecteds
					when 'o'; channel.ops
					when 'h'; channel.halfops
					when 'v'; channel.voices
				end
				
				param = params.shift
				next false unless param
				param.downcase!
				
				param = channel.users.find {|u| u.nick.downcase == param }
				next false unless param
				next false if list.include?(param) ^ !add
				
				if add
					list << param
				else
					list.delete param
				end
				
				next param.nick
				
			elsif 'beI'.include? char # TODO: Allow listing
				list = case char
					when 'b'; channel.bans
					when 'e'; channel.excepts
					when 'I'; channel.invex
				end
				
				param = params.shift
				next false unless param
				next false if list.include?(param) ^ !add
				
				if add
					list << param
				else
					list.delete param
				end
				
				next param
				
  		# Already set
  		elsif channel.modes.include?(char) ^ !add
  			
  			params.shift if 'fjklL'.include? char
  			
   			next false
   			
  		elsif add
  			params.shift if 'fjklL'.include? char
  			
				channel.modes << char
				
			else
  			params.shift if 'fjklL'.include? char
  			
				channel.modes = channel.modes.delete char
  		end
  		
  		true
  	end
  	channel.send_to_all path, :mode, channel.name, *str if str.any?
  	str
  end
  
  def parse_mode_string mode_str, valid_modes
  	set = true
  	
  	results = []
  	args = []
  	
  	mode_str.each_char do |mode_chr|
  		if mode_chr == '+'
  			set = true
  		elsif mode_chr == '-'
  			set = false
  		else
  			ret = valid_modes.include?(mode_chr) && yield(set, mode_chr)
  			next unless ret
  			
				results << [set, mode_chr]
				args << ret unless ret == true
  		end
  	end
  	
  	mode_str = ''
  	set = nil
  	
  	results.each do |(setter, mode)|
			if setter != set
				mode_str << (setter ? '+' : '-')
				set = setter
			end
			
			mode_str << mode
		end
		
		args.unshift mode_str
		args
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
		umodes.chars.select {|umode| has_umode?(umode) }.any?
	end
	
	def to_s
		path
	end
  
end
