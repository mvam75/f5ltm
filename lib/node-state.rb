#!/usr/bin/env ruby
# vim:expandtab shiftwidth=2 softtabstop=2
# written by Jos Backus /http://www.catnook.com/programs/f5-icontrol/

require 'rubygems'
require 'yaml'
require 'getoptions'

$: << File.join(ENV['HOME'], '/ops/lib') << '/cc/ops/lib'
require 'f5'

PROGNAME = File.basename($0)

def usage(msg=nil)
  Kernel.warn "#{PROGNAME}: #{msg}" if msg
  Kernel.abort "Usage: #{PROGNAME} [--config_file <filename>] <hostname> show|enable|disable <node> [...]"
end

opts = GetOptions.new(%w(config_file=s connect_timeout=i))

hostname, cmd, *nodes = ARGV

usage if nodes.empty?

options = {
  :config_file     => opts.config_file,
  :connect_timeout => opts.connect_timeout,
}

ObjectStatus = [:availability_status, :enabled_status, :status_description]
CMD_MAP = {
  'disable' => lambda {|node|
		 state = 'STATE_DISABLED'
                 node.set_state('STATE_DISABLED')
               },
  'enable'  => lambda {|node|
		 node.set_state('STATE_ENABLED')
               },
  'show'    => lambda {|node|
                 h = {
                   node.address => {
                     'monitor_status' => node.get_monitor_status,
                     'session_enabled_state' => node.get_session_enabled_state,
                     'object_status' => Hash[
                       *ObjectStatus.map {|what|
                         [what.to_s, node.get_object_status.send(what)]
                       }.flatten
                     ],
                   }
                 }
                 puts h.to_yaml
               },
}

usage("invalid command: #{cmd}") unless CMD_MAP.has_key? cmd

lb = F5::LoadBalancer.new(hostname, options)

nodes.map {|node| F5::LoadBalancer::Node.new(lb, node)}.each do |node|
  begin
    CMD_MAP[cmd].call(node)
  rescue HTTPClient::ConnectTimeoutError => exc
    abort "#{PROGNAME}: connect to #{hostname}: #{exc.message}"
  end
end

exit 0

