# this is our main file
#things to do

# make call to parse yaml file (vs_builder code)
# create monitor (f5_monitor_create_template)
# update monitor
## add http send/receive (f5_monitor_set_template_string_property)
# create pool (f5_pool_create)
# update pool members
## PGA (f5_poolmember_set_priority.rb)
# update pool
## enable PGA (f5_pool_set_min_active_members)
## bind monitor (pool_set_monitor_association)
# create SSL profile?
# create vs (f5_vs_create)
# update vs
## snat (f5_vs_set_snat_pool)
## ssl_profile?
## vlans
## connection mirroring (only for DB LB)
## bind irule (lowest priority)

## other ideas-
### decouple command line from methods.  could allow easier direct use of methods.
### most obvious in setting pool member priority

require 'yaml'
require 'ostruct'
require 'optparse'
require 'pp'
require 'ruby-debug'

class Optparser
  def self.parse(args)
    options = OpenStruct.new

    opts = OptionParser.new do |opts|
      
      opts.banner = "Usage: f5_pool_create.rb [options]"
      opts.separator ""
      opts.separator "Specific options:"
      
      options.vsconf = "../fixtures/virtual_servers.yaml"
      
           
      opts.on( "-f", "--config Config File", "YAML config file") do |file|
        options.vsconf = file || "../fixtures/virtual_servers.yaml"
      end
      
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
      exit
      end
    end
    opts.parse!(args)
    options
  end # self.parse
end #class Optparser

def create_member_array(member_list)
  member_list.collect {|member| member["memberdef"]}
end

def create_member_flag_list(member_list)
  member_flags = ""
  member_list.each do |member|
    member_flags << "--member #{member} "
  end
  member_flags
end
# get command line options
options = Optparser.parse(ARGV)

# exit if required parameters are missing
# this may need some work
# maybe swap optparse for trollop?
REQ_PARAMS = [:vsconf]
REQ_PARAMS.find do |p|
  Kernel.abort "Missing Argument: #{p}" unless options.respond_to?(p)
end

# read into an open struct
vs_yaml_conf = OpenStruct.new(YAML.load_file(options.vsconf))

# presume that services are split by "servicen" in yaml conf
service_list = vs_yaml_conf.methods.grep(/service\d+$/)
#pp vs_yaml_conf.pool["name"]

def update_object_name(name, suffix, fqdn)
  if name.empty? and not fqdn.empty?
    "#{fqdn}_#{suffix}"
  elsif name.end_with?(suffix)
    "#{name}"
  else
    "#{name}_#{suffix}"
  end
end

def correct_member_ports(member_list, pool_port)
  # checks for an IP4 addr that is not followed by a colon and digits
  # i.e. skips over any member that properly defines IP:Port
  # meant to allow port to be specified at both the pool level or 
  # overriden at the pool member level
  
  members_with_ports = member_list.grep(/(\d+\.\d+\.\d+\.\d+:\d+)/)
  members_wo_ports = member_list.grep(/\b(\d+\.\d+\.\d+\.\d+)\b(?!:\d+)/){$1}
  members_with_ports.concat(members_wo_ports.grep(/(\d+\.\d+\.\d+\.\d+)/){|ip| "#{ip}:#{pool_port}"})
end

if service_list.empty?
  # create vs/pool/monitor/etc for the single service defined
  # how to DRY this up?
  ### creating pool
  pp "whole pool conf: #{vs_yaml_conf.pool}"
  pp "pool mem conf: #{vs_yaml_conf.pool["pool_members"]}"
  
  vs_yaml_conf.pool["name"] = update_object_name(vs_yaml_conf.pool["name"].to_s, vs_yaml_conf.pool["port"], vs_yaml_conf.main["fqdn"].to_s)
    
  member_list = create_member_array(vs_yaml_conf.pool["pool_members"])
  member_list = correct_member_ports(member_list,vs_yaml_conf.pool["port"])
  
  #updating memberdef in yml config obj
  vs_yaml_conf.pool["pool_members"].each do |pool_mem|
    member_list.each do |cur_mem|
      if cur_mem.to_s.include?(pool_mem["memberdef"].to_s) 
        pool_mem["memberdef"] = cur_mem
      end
    end
  end
    
  member_flag_list = create_member_flag_list(member_list)
  pp "creating pool..."
  output = %x{ruby -W0 f5_pool_create.rb --name #{vs_yaml_conf.pool["name"]} #{member_flag_list} --bigip 192.168.106.13}
  
  ### update pool member priority
  pp "updating pool member priorities..."
  vs_yaml_conf.pool["pool_members"].each do |pool_mem|
    output = %x{ruby -W0 f5_poolmember_set_priority.rb --bigip 192.168.106.13 --name #{vs_yaml_conf.pool["name"]} --member #{pool_mem["memberdef"]} --member_priority #{pool_mem["priority"]} }
  end
  
  ### turn on PGA
  output = %x{ruby -W0 f5_pool_set_min_active_members.rb --bigip 192.168.106.13 --pool_name #{vs_yaml_conf.pool["name"]} --min_active_members #{vs_yaml_conf.pool["min_active_members"]} }
  
  ## creating monitor template
  pp "creating monitor template..."
  vs_yaml_conf.monitor["name"] = update_object_name(vs_yaml_conf.monitor["name"].to_s, "alive", vs_yaml_conf.main["fqdn"].to_s)
  
  monoutput = %x{ruby -W0 f5_monitor_create_template.rb --bigip 192.168.106.13  --name #{vs_yaml_conf.monitor["name"]} --parent_template #{vs_yaml_conf.monitor["type"]} --interval #{vs_yaml_conf.monitor["interval"]} --timeout #{vs_yaml_conf.monitor["timeout"]}}
  
  ## set monitor send/receive strings
  ## assumes http/https monitor type
  
  send_string_suffix = vs_yaml_conf.monitor["send"].to_s.concat(' HTTP/1.1\\r\\nHost: bigipalive.theplatform.com\\r\\n\\r\\n')
  
  monoutput = %x{ruby -W0 f5_monitor_set_template_string_property.rb --bigip 192.168.106.13 --monitor_name #{vs_yaml_conf.monitor["name"]} --string_property_type "STYPE_SEND" --string_value "#{send_string_suffix}"}
 
  monoutput = %x{ruby -W0 f5_monitor_set_template_string_property.rb --bigip 192.168.106.13 --monitor_name #{vs_yaml_conf.monitor["name"]} --string_property_type "STYPE_RECEIVE" --string_value "#{vs_yaml_conf.monitor["recv"]}"}

  ### associate monitor template with pool
  monassoc_output = %x{ruby -W0 f5_pool_set_monitor_association.rb --bigip 192.168.106.13 --pool_name #{vs_yaml_conf.pool["name"]} --monitor_name #{vs_yaml_conf.monitor["name"]} }
  
  ### create the virtual server
  pp "creating virtual server..."
  vs_yaml_conf.virtual_server["name"] = update_object_name(vs_yaml_conf.virtual_server["name"].to_s, vs_yaml_conf.virtual_server["port"], vs_yaml_conf.main["fqdn"].to_s)
  
  vs_yaml_conf.virtual_server["default_pool_name"] = update_object_name(vs_yaml_conf.virtual_server["default_pool_name"].to_s, vs_yaml_conf.pool["port"], vs_yaml_conf.main["fqdn"].to_s)
  
  output = %x{ruby -W0 f5_vs_create.rb --bigip 192.168.106.13 --address #{vs_yaml_conf.virtual_server["address"].to_s}  --mask #{vs_yaml_conf.virtual_server["netmask"]} --name #{vs_yaml_conf.virtual_server["name"]} --port #{vs_yaml_conf.virtual_server["port"]} --protocol #{vs_yaml_conf.virtual_server["protocol"]} --resource_type #{vs_yaml_conf.virtual_server["resource_type"]} --pool_name #{vs_yaml_conf.virtual_server["default_pool_name"]} --profile_context #{vs_yaml_conf.virtual_server["profile_context"]}}
  
  ###### update VS settings ######
  ### add snat if necessary
  unless vs_yaml_conf.virtual_server["snat"].nil?
    output = %x{ruby -W0 f5_vs_set_snat_pool.rb --bigip 192.168.106.13 --vs_name #{vs_yaml_conf.virtual_server["name"]} --snat_pool_name #{vs_yaml_conf.virtual_server["snat"]} }
  end
else ### loop through each service and create vs/pool/monitor/etc
    
  service_list.each do |service_num|
    
    # create an array of objects.  there might be an easier way to do this,
    # we get the ability to use "." notation
    current_service_conf = OpenStruct.new(vs_yaml_conf.send(service_num))
    
    ### creating pool
    pp "creating pool..."
    current_service_conf.pool["name"] = update_object_name(current_service_conf.pool["name"].to_s, current_service_conf.pool["port"], current_service_conf.main["fqdn"].to_s)
    
    member_list = create_member_array(current_service_conf.pool["pool_members"])
    member_list = correct_member_ports(member_list,current_service_conf.pool["port"])
    member_flag_list = create_member_flag_list(member_list)
    
    #updating memberdef in yml config obj
    current_service_conf.pool["pool_members"].each do |pool_mem|
      member_list.each do |cur_mem|
        if cur_mem.to_s.include?(pool_mem["memberdef"].to_s) 
          pool_mem["memberdef"] = cur_mem
        end
      end
    end
  
    output = %x{ruby -W0 f5_pool_create.rb --name #{current_service_conf.pool["name"]} #{member_flag_list} --bigip 192.168.106.13}
    
    ### update pool member priority
    pp "updating pool member priorities"
    
    current_service_conf.pool["pool_members"].each do |pool_mem|
      output = %x{ruby -W0 f5_poolmember_set_priority.rb --bigip 192.168.106.13 --name #{current_service_conf.pool["name"]} --member #{pool_mem["memberdef"]} --member_priority #{pool_mem["priority"]} }
    end
    
    ### turn on PGA
    pp "turning on PGA"
    output = %x{ruby -W0 f5_pool_set_min_active_members.rb --bigip 192.168.106.13 --pool_name #{current_service_conf.pool["name"]} --min_active_members #{current_service_conf.pool["min_active_members"]} }
    
    ## creating monitor template
    pp "creating monitor template..."
    current_service_conf.monitor["name"] = update_object_name(current_service_conf.monitor["name"].to_s, "alive", current_service_conf.main["fqdn"].to_s)
    
    monoutput = %x{ruby -W0 f5_monitor_create_template.rb --bigip 192.168.106.13  --name #{current_service_conf.monitor["name"]} --parent_template #{current_service_conf.monitor["type"]} --interval #{current_service_conf.monitor["interval"]} --timeout #{current_service_conf.monitor["timeout"]}}
    
    ## set monitor send/receive strings
    ## assumes http/https monitor type
    pp "setting monitor send/receive strings..."
    
    send_string_suffix = current_service_conf.monitor["send"].to_s.concat(' HTTP/1.1\\r\\nHost: bigipalive.theplatform.com\\r\\n\\r\\n')
    
    monoutput = %x{ruby -W0 f5_monitor_set_template_string_property.rb --bigip 192.168.106.13 --monitor_name #{current_service_conf.monitor["name"]} --string_property_type "STYPE_SEND" --string_value "#{send_string_suffix}"}
   
    monoutput = %x{ruby -W0 f5_monitor_set_template_string_property.rb --bigip 192.168.106.13 --monitor_name #{current_service_conf.monitor["name"]} --string_property_type "STYPE_RECEIVE" --string_value "#{current_service_conf.monitor["recv"]}"}

    ### associate monitor template with pool
    pp "associating monitor with pool..."
    monassoc_output = %x{ruby -W0 f5_pool_set_monitor_association.rb --bigip 192.168.106.13 --pool_name #{current_service_conf.pool["name"]} --monitor_name #{current_service_conf.monitor["name"]} }
    
    ### create the virtual server
    pp "creating virtual server..."
    current_service_conf.virtual_server["name"] = update_object_name(current_service_conf.virtual_server["name"].to_s, current_service_conf.virtual_server["port"], current_service_conf.main["fqdn"].to_s)
    
    current_service_conf.virtual_server["default_pool_name"] = update_object_name(current_service_conf.virtual_server["default_pool_name"].to_s, current_service_conf.pool["port"], current_service_conf.main["fqdn"].to_s)
    
    output = %x{ruby -W0 f5_vs_create.rb --bigip 192.168.106.13 --address #{current_service_conf.virtual_server["address"].to_s}  --mask #{current_service_conf.virtual_server["netmask"]} --name #{current_service_conf.virtual_server["name"]} --port #{current_service_conf.virtual_server["port"]} --protocol #{current_service_conf.virtual_server["protocol"]} --resource_type #{current_service_conf.virtual_server["resource_type"]} --pool_name #{current_service_conf.virtual_server["default_pool_name"]} --profile_context #{current_service_conf.virtual_server["profile_context"]}}
    
    ###### update VS settings ######
    ### add snat if necessary
    unless current_service_conf.virtual_server["snat"].nil?
      pp "adding snat pool..."
      output = %x{ruby -W0 f5_vs_set_snat_pool.rb --bigip 192.168.106.13 --vs_name #{current_service_conf.virtual_server["name"]} --snat_pool_name #{current_service_conf.virtual_server["snat"]} }
    end
      
  end
end
