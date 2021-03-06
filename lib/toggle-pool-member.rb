#!/usr/bin/env ruby
# vim:expandtab shiftwidth=2 softtabstop=2
# Original Code by Jos Backus http://www.catnook.com/programs/f5-icontrol/
# Additional code by Andy Litzinger https://github.com/ajlitzin/f5ltm

require 'f5'

Member = Struct.new(:address, :port) do
  def to_hash
    { 'address' => self.address, 'port' => self.port }
  end
end

def get_pool_member_states(lb, pools)
  lb.icontrol.locallb.pool_member.get_session_enabled_state(pools.map {|pool| pool.name})
end

def show_pool_members(lb, pools)
  member_state_lists = get_pool_member_states(lb, pools)

  puts "Available pool members"
  puts "======================"
  pools.each_with_index do |pool, i|
    puts "pool #{pool.name}"
    puts '{'
    member_state_list = member_state_lists[i]
    member_state_list.each do |member_state|
      member = member_state["member"]
      addr = member["address"]
      port = member["port"]

      session_state = member_state["session_state"]

      puts "    #{addr}:#{port} (#{session_state})"
    end
    puts '}'
  end
end

def toggle_pool_member(lb, pool, member_def)
  node_ip, node_port = member_def.split(/:/, 2)
  node_port = 0 if node_port.nil? or node_port.empty?
  member = Member.new(node_ip, node_port)

  pool_member_state = get_pool_member_state(lb, pool, member)

  # Set the state to be toggled to.
  toggle_state = 'STATE_DISABLED'
  toggle_state = case pool_member_state
  when 'STATE_DISABLED'; 'STATE_ENABLED'
  when 'STATE_ENABLED'; 'STATE_DISABLED'
  else
    raise "unable to find member #{member_def} in pool #{pool.name}"
  end

  member_session_state = {
    'member'        => member.to_hash,
    'session_state' => toggle_state,
  }
  member_session_state_list = [member_session_state]
  member_session_state_lists = [member_session_state_list]

  lb.icontrol.locallb.pool_member.set_session_enabled_state([pool.name], member_session_state_lists)
  puts "Pool #{pool.name} member {#{node_ip}:#{node_port}} state set from '#{pool_member_state}' to '#{toggle_state}'"
end

def enable_pool_member(lb, pool, member_def)
  node_ip, node_port = member_def.split(/:/, 2)
  node_port = 0 if node_port.nil? or node_port.empty?
  member = Member.new(node_ip, node_port)

  member_session_state = {
    'member'        => member.to_hash,
    'session_state' => STATE_ENABLED,
  }
  member_session_state_list = [member_session_state]
  member_session_state_lists = [member_session_state_list]

  lb.icontrol.locallb.pool_member.set_session_enabled_state([pool.name], member_session_state_lists)
  puts "Pool #{pool.name} member {#{node_ip}:#{node_port}} state set to STATE_ENABLED'"
end


def disable_pool_member(lb, pool, member_def)
  node_ip, node_port = member_def.split(/:/, 2)
  node_port = 0 if node_port.nil? or node_port.empty?
  member = Member.new(node_ip, node_port)

  member_session_state = {
    'member'        => member.to_hash,
    'session_state' => STATE_DISABLED,
  }
  member_session_state_list = [member_session_state]
  member_session_state_lists = [member_session_state_list]

  lb.icontrol.locallb.pool_member.set_session_enabled_state([pool.name], member_session_state_lists)
  puts "Pool #{pool.name} member {#{node_ip}:#{node_port}} state set to STATE_DISABLED"
end



def get_pool_member_state(lb, pool, member_def)
  state = nil
  member_state_lists = get_pool_member_states(lb, [pool])
  member_state_list = member_state_lists.first
  member_state_list.each do |member_state|
    member = member_state['member']
    if member.address == member_def.address and
      member.port.to_i == member_def.port.to_i
      state = member_state['session_state']
    end
  end
  state
end

Kernel.abort "Usage: #{$0} <hostname> [pool [member]]" if ARGV.empty?

hostname, pool, member = ARGV

lb = F5::LoadBalancer.new(hostname, :config_file => 'config-admin.yaml', :connect_timeout => 10)

if pool
  pool = F5::LoadBalancer::Pool.new(lb, pool)
  if member
    toggle_pool_member(lb, pool, member)
  else
    show_pool_members(lb, [pool])
  end
else
  show_pool_members(lb, lb.pools)
end

exit

