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

# Thanks to Tsion for the Server class
require 'socket'

class IRCServer
  attr_accessor :debug, :clients, :channels, :name, :max_clients, :listeners, :listen_socks, :socks, :running
  
	def initialize(name=nil)
    @debug = true
    @clients = []
    @channels = []
    @name = name
    @max_clients = 20 # TODO: Is this used?
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
		
		#rescue => error
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
			p error
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
	
	# Helper socks for client instances to use
	
	def validate_nick(nick)
		nick =~ /^[a-zA-Z\[\]_|`^][a-zA-Z0-9\[\]_|`^]{0,#{ServerConfig.max_nick_length.to_i - 1}}$/
	end
	def validate_channel(channel)
		channel =~ /^\#[a-zA-Z0-9`~!@\#$%^&*\(\)\'";|}{\]\[.<>?]{0,#{ServerConfig.max_channel_length.to_i - 2}}$/
	end
end
