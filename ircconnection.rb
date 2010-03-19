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

require 'rubygems'
require 'eventmachine'
require 'socket'

class IRCConnection < EventMachine::Connection
  attr_accessor :server, :client, :port, :ip

  def initialize server
    super()

    @server = server
    @client = IRCClient.new self
    @buffer	= ''

    @server.socks << self
    @server.clients << @client
  end

  def post_init
    sleep 0.25
    @port, @ip = Socket.unpack_sockaddr_in get_peername
    puts "Connected to #{@ip}:#{@port}"
  end

  def send_line params
    params = params.join ' ' if params.is_a? Array
    send_data "#{params.gsub("\n", '')}\n"
  end

  def receive_data data
    @buffer += data
    while @buffer.include? "\n"
      receive_line @buffer.slice!(0, @buffer.index("\n")+1).chomp
    end
  end

  def receive_line line
    puts line
    @client.handle_packet line
  end

  def unbind
    @client.close 'Client disconnected'
    puts "connection closed to #{@ip}:#{@port}"
    @server.remove_sock self
  end
end
