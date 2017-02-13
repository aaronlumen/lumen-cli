# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end

	def handle(args) 
		usage = "Usage: morpheus apps [list,details,add,update,remove,add-instance,remove-instance,logs,firewall_disable,firewall_enable,security_groups,apply_security_groups] [name]"
		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				update(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'add-instance'
				add_instance(args[1..-1])
			when 'remove-instance'
				remove_instance(args[1..-1])
			when 'stop'
				stop(args[1..-1])
			when 'start'
				start(args[1..-1])
			when 'restart'
				restart(args[1..-1])
			when 'logs'
				logs(args[1..-1])
			# when 'stats'
			# 	stats(args[1..-1])
			# when 'envs'
			# 	envs(args[1..-1])
			# when 'setenv'
			# 	setenv(args[1..-1])	
			# when 'delenv'
			# 	delenv(args[1..-1])
			when 'firewall_disable'
				firewall_disable(args[1..-1])	
			when 'firewall_enable'
				firewall_enable(args[1..-1])	
			when 'security_groups'	
				security_groups(args[1..-1])	
			when 'apply_security_groups'	
				apply_security_groups(args[1..-1])		
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps list"
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)
		connect(options)
		begin
      params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @apps_interface.get(params)
			
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
				return
			end
			apps = json_response['apps']
			print "\n" ,cyan, bold, "Morpheus Apps\n","==================", reset, "\n\n"
			if apps.empty?
				puts yellow,"No apps currently configured.",reset
			else
				print_apps_table(apps)
			end
			print reset,"\n\n"
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def add(args)
		usage = "Usage: morpheus apps add"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
				options[:group_name] = val
			end
			opts.on( '-G', '--group-id ID', "Group Id" ) do |val|
				options[:group_id] = val
			end
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse(args)
    connect(options)
    begin
  		
  		# use active group by default
			if !options[:group_name] && !options[:group_id]
				options[:group_id] = @active_groups[@appliance_name.to_sym]
			end
			group = find_group_from_options(options)

			payload = {
				'app' => {}
			}

			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'}], options[:options])
			payload['app']['name'] = v_prompt['name']
			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false}], options[:options])
			payload['app']['description'] = v_prompt['description']
			if group
				payload['app']['site'] = {id: group["id"]}
			else
				v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => get_available_groups(), 'required' => true}], options[:options])
				payload['app']['site'] = {id: v_prompt["group"]}
			end

			# todo: allow adding instances with creation..

      json_response = @apps_interface.create(payload)

      if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/apps", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added app #{payload['app']['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end

	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps details [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		begin
			app = find_app_by_name_or_id(args[0])
			if options[:json]
				print JSON.pretty_generate({app: app})
				return
			end
			
			print "\n" ,cyan, bold, "App Details\n","==================", reset, "\n\n"
			print cyan
			puts "ID: #{app['id']}"
			puts "Name: #{app['name']}"
			puts "Description: #{app['description']}"
			puts "Account: #{app['account'] ? app['account']['name'] : ''}"
			# puts "Group: #{app['siteId']}"
			
			stats = app['stats']
			print cyan, "Memory: \t#{Filesize.from("#{stats['usedMemory']} B").pretty} / #{Filesize.from("#{stats['maxMemory']} B").pretty}\n"
			print cyan, "Storage: \t#{Filesize.from("#{stats['usedStorage']} B").pretty} / #{Filesize.from("#{stats['maxStorage']} B").pretty}\n\n",reset

			app_tiers = app['appTiers']
			if app_tiers.empty?
				puts yellow, "This app is empty", reset
			else
				app_tiers.each do |app_tier|
					print "\n" ,cyan, bold, "Tier: #{app_tier['tier']['name']}\n","==================", reset, "\n\n"
					print cyan
					instances = (app_tier['appInstances'] || []).collect {|it| it['instance']}
					if instances.empty?
						puts yellow, "This tier is empty", reset
					else
						instance_table = instances.collect do |instance|
							status_string = instance['status']
							if status_string == 'running'
								status_string = "#{green}#{status_string.upcase}#{cyan}"
							elsif status_string == 'stopped' or status_string == 'failed'
								status_string = "#{red}#{status_string.upcase}#{cyan}"
							elsif status_string == 'unknown'
								status_string = "#{white}#{status_string.upcase}#{cyan}"
							else
								status_string = "#{yellow}#{status_string.upcase}#{cyan}"
							end
							connection_string = ''
							if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
								connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
							end
							{id: instance['id'], name: instance['name'], connection: connection_string, environment: instance['instanceContext'], nodes: instance['containers'].count, status: status_string, type: instance['instanceType']['name'], group: !instance['group'].nil? ? instance['group']['name'] : nil, cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil}
						end
						tp instance_table, :id, :name, :cloud, :type, :environment, :nodes, :connection, :status
					end
				end
			end
			print cyan

			print reset,"\n"

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		usage = "Usage: morpheus apps update [name] [options]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse(args)
    if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
    connect(options)

    begin
  		
  		app = find_app_by_name_or_id(args[0])

			# group = find_group_from_options(options)

			payload = {
				'app' => {id: app["id"]}
			}

			update_app_option_types = [
				{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'},
				{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false}
			]

			params = options[:options] || {}

      if params.empty?
        puts "\n#{usage}\n"
        option_lines = update_app_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      app_keys = ['name', 'description']
      params = params.select {|k,v| app_keys.include?(k) }
      payload['app'].merge!(params)
			
      json_response = @apps_interface.update(app["id"], payload)

      if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "PUT #{@appliance_url}/api/apps", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated app #{payload['app']['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end


	def add_instance(args)
		usage = "Usage: morpheus apps add-instance [name] [instance] [tier]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse(args)
    if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		# optional [tier] and [instance] arguments
		if args[1] && args[1] !~ /\A\-/
			options[:instance_name] = args[1]
			if args[2] && args[2] !~ /\A\-/
				options[:tier_name] = args[2]
			end
		end
    connect(options)
    begin
  		
  		app = find_app_by_name_or_id(args[0])

  		# Only supports adding an existing instance right now..

  		payload = {}

  		if options[:instance_name]
  			instance = find_instance_by_name_or_id(options[:instance_name])
  		else
  			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
  			instance = find_instance_by_name_or_id(v_prompt['instance'])
  		end
  		payload[:instanceId] = instance['id']

  		if options[:tier_name]
  			payload[:tierName] = options[:tier_name]
  		else
  			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tier', 'fieldLabel' => 'Tier', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
  			payload[:tierName] = v_prompt['tier']
  		end

      json_response = @apps_interface.add_instance(app['id'], payload)

      if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/apps/#{app['id']}/add-instance", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance #{instance['name']} to app #{app['name']}"
        list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps remove [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)

		begin
			app = find_app_by_name_or_id(args[0])
			unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the app '#{app['name']}'?", options)
				exit 1
			end
			@apps_interface.destroy(app_results['app']['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove_instance(args)
		usage = "Usage: morpheus apps remove-instance [name] [instance]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse(args)
    if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		# optional [tier] and [instance] arguments
		if args[1] && args[1] !~ /\A\-/
			options[:instance_name] = args[1]
		end
    connect(options)
    begin
  		
  		app = find_app_by_name_or_id(args[0])

  		payload = {}

  		if options[:instance_name]
  			instance = find_instance_by_name_or_id(options[:instance_name])
  		else
  			v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
  			instance = find_instance_by_name_or_id(v_prompt['instance'])
  		end
  		payload[:instanceId] = instance['id']

      json_response = @apps_interface.remove_instance(app['id'], payload)

      if options[:dry_run]
				print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
				print cyan
				print "Request: ", "\n"
				print reset
				print "POST #{@appliance_url}/api/apps/#{app['id']}/remove-instance", "\n\n"
				print cyan
				print "JSON: ", "\n"
				print reset
				print JSON.pretty_generate(payload)
				print "\n"
				print reset
				return
			end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed instance #{instance['name']} from app #{app['name']}"
        list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
	end

	def logs(args) 
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps logs [name]"
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		begin
			app = find_app_by_name_or_id(args[0])
			containers = []
			app['appTiers'].each do |app_tier|
				app_tier['appInstances'].each do |app_instance|
					containers += app_instance['instance']['containers']
				end
			end
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			logs = @logs_interface.container_logs(containers, params)
			if options[:json]
				print JSON.pretty_generate(logs)
				print "\n"
			else
				logs['data'].reverse.each do |log_entry|
					log_level = ''
					case log_entry['level']
						when 'INFO'
							log_level = "#{blue}#{bold}INFO#{reset}"
						when 'DEBUG'
							log_level = "#{white}#{bold}DEBUG#{reset}"
						when 'WARN'
							log_level = "#{yellow}#{bold}WARN#{reset}"
						when 'ERROR'
							log_level = "#{red}#{bold}ERROR#{reset}"
						when 'FATAL'
							log_level = "#{red}#{bold}FATAL#{reset}"
					end
					puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message']}"
				end
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

=begin
	def stop(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps stop [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end
			@apps_interface.stop(app_results['apps'][0]['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def start(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps start [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end
			@apps_interface.start(app_results['apps'][0]['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def restart(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps restart [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)
		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end
			@apps_interface.restart(app_results['apps'][0]['id'])
			list([])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end
=end

	def firewall_disable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps firewall_disable [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)

		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end
			@apps_interface.firewall_disable(app_results['apps'][0]['id'])
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def firewall_enable(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps firewall_enable [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)

		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end
			@apps_interface.firewall_enable(app_results['apps'][0]['id'])
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def security_groups(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus apps security_groups [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		connect(options)

		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end

			app_id = app_results['apps'][0]['id']
			json_response = @apps_interface.security_groups(app_id)

			securityGroups = json_response['securityGroups']
			print "\n" ,cyan, bold, "Morpheus Security Groups for App:#{app_id}\n","==================", reset, "\n\n"
			print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
			if securityGroups.empty?
				puts yellow,"No security groups currently applied.",reset
			else
				securityGroups.each do |securityGroup|
					print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
				end
			end
			print reset,"\n\n"

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def apply_security_groups(args)
		usage = <<-EOF
Usage: morpheus apps apply_security_groups [name]
EOF

		options = {}
		clear_or_secgroups_specified = false
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			opts.on( '-c', '--clear', "Clear all security groups" ) do
				options[:securityGroupIds] = []
				clear_or_secgroups_specified = true
			end
			opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
				options[:securityGroupIds] = secgroups.split(",")
				clear_or_secgroups_specified = true
			end
			opts.on( '-h', '--help', "Prints this help" ) do
				puts opts
				exit
			end
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		if !clear_or_secgroups_specified 
			puts usage
			exit 1
		end

		connect(options)

		begin
			app_results = @apps_interface.get({name: args[0]})
			if app_results['apps'].empty?
				print_red_alert "App not found by name #{args[0]}"
				exit 1
			end

			@apps_interface.apply_security_groups(app_results['apps'][0]['id'], options)
			security_groups([args[0]])
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

private

	def find_app_by_id(id)
		app_results = @apps_interface.get(id.to_i)
		if app_results['app'].empty?
			print_red_alert "App not found by id #{id}"
			exit 1
		end
		return app_results['app']
	end

	def find_app_by_name(name)
		app_results = @apps_interface.get({name: name})
		if app_results['apps'].empty?
			print_red_alert "App not found by name #{name}"
			exit 1
		end
		return app_results['apps'][0]
	end

	def find_app_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_app_by_id(val)
		else
			return find_app_by_name(val)
		end
	end

	def find_instance_by_id(id)
		instance_results = @instances_interface.get(id.to_i)
		if instance_results['instance'].empty?
			print_red_alert "Instance not found by id #{id}"
			exit 1
		end
		return instance_results['instance']
	end

	def find_instance_by_name(name)
		instance_results = @instances_interface.get({name: name})
		if instance_results['instances'].empty?
			print_red_alert "Instance not found by name #{name}"
			exit 1
		end
		return instance_results['instances'][0]
	end

	def find_instance_by_name_or_id(val)
		if val.to_s =~ /\A\d{1,}\Z/
			return find_instance_by_id(val)
		else
			return find_instance_by_name(val)
		end
	end

	def print_apps_table(apps, opts={})
    table_color = opts[:color] || cyan
    rows = apps.collect do |app|
    	instances_str = (app['instanceCount'].to_i == 1) ? "1 Instance" : "#{app['instanceCount']} Instances"
			containers_str = (app['containerCount'].to_i == 1) ? "1 Container" : "#{app['containerCount']} Containers"
    	status_string = app['status']
    	if app['instanceCount'].to_i == 0
    		# show this instead of WARNING
    		status_string = "#{white}EMPTY#{table_color}"
			elsif status_string == 'running'
				status_string = "#{green}#{status_string.upcase}#{table_color}"
			elsif status_string == 'stopped' or status_string == 'failed'
				status_string = "#{red}#{status_string.upcase}#{table_color}"
			elsif status_string == 'unknown'
				status_string = "#{white}#{status_string.upcase}#{table_color}"
			else
				status_string = "#{yellow}#{status_string.upcase}#{table_color}"
			end
			
      {
        id: app['id'], 
        name: app['name'], 
        instances: instances_str,
        containers: containers_str,
        account: app['account'] ? app['account']['name'] : nil, 
        status: status_string, 
        #dateCreated: format_local_dt(app['dateCreated']) 
      }
    end
    
    print table_color
    tp rows, [
      :id, 
      :name, 
      :instances,
      :containers,
      #:account, 
      :status,
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end

  def generate_id(len=16)
    id = ""
    len.times { id << (1 + rand(9)).to_s }
    id
  end

end
