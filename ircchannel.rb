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

class IRCChannel
	attr_reader :name, :users
	attr_reader :owners, :protecteds, :ops, :halfops, :voices
	attr_reader :bans, :invex, :excepts
	attr_reader :modes, :mode_timestamp
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
		@mode_timestamp = Time.now.to_i
		
		@topic = nil
		@topic_author = nil
		@topic_timestamp = nil
	end

	def self.find(name)
		name = name.downcase
		$server.channels.each do |channel|
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
	
	def modes=(modes)
		@modes = modes
		@modes_timestamp = Time.now
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
