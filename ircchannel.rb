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
	
	def initialize name
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
		@mode_timestamp = Time.now
	end
	
	def send_to_all *args
		@users.each {|user| user.send *args }
	end
	
	def send_to_all_except nontarget, *args
		@users.each {|user| user.send *args if user != nontarget }
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
		send_to_all_except sender, sender.path, :privmsg, @name, message
	end
	def notice(sender, message)
		send_to_all_except sender, sender.path, :notice, @name, message
	end
	
	def join client
		@users << client
		send_to_all client.path, :join, @name
	end
	
	def part client, message='Leaving'
		send_to_all client.path, :part, @name, message
		remove client
	end
	
	def kick client, kicker, reason=nil
		send_to_all kicker, :kick, @name, client.nick, reason
		remove client
	end
	
	def remove client
		[@users, @owners, @protecteds, @ops, @halfops, @voices].each do |list|
			list.delete client
		end
	end
	
	def empty?
		@users.empty?
	end
	
	def set_topic topic, author
		@topic = topic
		@topic_timestamp = Time.now
		@topic_author = author.nick
		send_to_all author, :topic, @name, topic
	end
	
	def has_mode? mode
		@modes.include? mode
	end
	def has_any_mode? modes
		@modes.split('').select {|mode| has_mode?(mode) }.any?
	end
end
