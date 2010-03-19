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

class IRCServer
  attr_accessor :debug, :clients, :channels, :name, :socks, :running

  def initialize name=nil
    @name = name
    
    @clients = []
    @channels = []
    @socks = []
    
    @debug = true
    @running = false
  end

  def log msg
    puts "[#{Time.new.ctime}] #{msg}"
  end
  def log_nick nick, msg
    log "#{@host}:#{@port} #{nick}\t#{msg}"
  end

  def remove_client client
    remove_sock client.conn
  end
  def remove_sock sock
    @socks.delete sock
    @clients.delete sock.client
  end
  
  def find_user nick
    return nick if nick.is_a? IRCClient
    
    nick = nick.downcase
    @clients.find {|client| client.nick.downcase == nick }
  end
  def find_channel name
    return name if name.is_a? IRCChannel
    
    name = name.downcase
    @channels.find {|chan| chan.name.downcase == name }
  end
  
  def find_or_create_channel name
    channel = find_channel name
    return channel if channel

    channel = IRCChannel.new name
    @channels << channel
    channel
  end
  
  def destroy_channel channel, reason='OM NOM NOM'
    channel.users.each do |user|
      user.kicked_from channel, @name, reason
    end
    @channels.delete channel
  end

  # Helper socks for client instances to use

  def validate_nick nick
    nick =~ /^[a-zA-Z\[\]_|`^][a-zA-Z0-9\[\]_|`^]{0,#{ServerConfig.max_nick_length.to_i - 1}}$/
  end
  def validate_chan channel
    channel =~ /^\#[a-zA-Z0-9`~!@\#$%^&*\(\)\'";|}{\]\[.<>?]{0,#{ServerConfig.max_channel_length.to_i - 2}}$/
  end
end
