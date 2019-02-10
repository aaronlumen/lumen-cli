# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require "shellwords"
require 'readline'
require 'logger'
require 'fileutils'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/error_handler'
require 'morpheus/cli/expression_parser'
require 'morpheus/terminal'

#class Morpheus::Cli::Shell < Morpheus::Terminal
class Morpheus::Cli::Shell
  include Morpheus::Cli::CliCommand

  @@instance = nil

  def self.has_instance?
    defined?(@@instance) && @@instance
  end

  def self.instance
    @@instance ||= reload_instance
  end

  def self.reload_instance
    @@instance = self.new
  end

  def self.insecure
    !!(defined?(@@insecure) && @@insecure == true)
  end

  attr_accessor :prompt #, :angry_prompt

  def initialize()
    @@instance = self
    reinitialize()
  end

  def reinitialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    @current_remote = ::Morpheus::Cli::Remote.load_active_remote()
    if @current_remote
      @appliance_name, @appliance_url = @current_remote[:name], @current_remote[:host]
      # @current_username = @current_remote[:username] || '(anonymous)'
      @current_username = @current_remote[:username] || ''
    else
      @appliance_name, @appliance_url = nil, nil
      @current_username = nil
    end
    #connect()
    #raise "one shell only" if @@instance
    @@instance = self
    recalculate_prompt()
    recalculate_auto_complete_commands()
  end

  # def connect(opts)
  #   @api_client = establish_remote_appliance_connection(opts)
  # end

  def recalculate_prompt()
    # custom prompts.. this is overkill and perhaps a silly thing..
    # Example usage:
    # MORPHEUS_PS1="[%remote] %cyan %username morph> " morpheus shell --debug
    #@prompt = Morpheus::Terminal.instance.prompt.to_s #.dup
    @prompt = my_terminal.prompt

    variable_map = Morpheus::Cli::Echo.variable_map
    # variable_map = {
    #   '%cyan' => cyan, '%magenta' => magenta, '%red' => red, '%mgreen' => green, '%yellow' => yellow, '%dark' => dark, '%reset' => reset,
    #   '%remote' => @appliance_name.to_s, '%remote_url' => @appliance_url.to_s, 
    #   '%username' => @current_username.to_s
    # }
    @calculated_prompt = @prompt.to_s.dup
    variable_map.each do |k, v|
      @calculated_prompt.gsub!(k.to_s, v.to_s)
    end
    # cleanup empty brackets caused by var value
    @calculated_prompt = @calculated_prompt.gsub("[]", "").gsub("<>", "").gsub("{}", "")
    #@calculated_prompt = @calculated_prompt.strip
    # @calculated_prompt = "#{@calculated_prompt}#{reset} "
    @calculated_prompt
  end

  def recalculate_auto_complete_commands
    @morpheus_commands = Morpheus::Cli::CliRegistry.all.keys.reject {|k| [:shell].include?(k) }
    @shell_commands = [:clear, :history, :'flush-history', :reload!, :help, :exit]
    @alias_commands = Morpheus::Cli::CliRegistry.all_aliases.keys
    @exploded_commands = []
    Morpheus::Cli::CliRegistry.all.each do |cmd, klass|
      @exploded_commands << cmd.to_s
      subcommands = klass.subcommands rescue []
      subcommands.keys.each do |sub_cmd|
        @exploded_commands << "#{cmd} #{sub_cmd}"
      end
    end
    @auto_complete_commands = (@exploded_commands + @shell_commands + @alias_commands).collect {|it| it.to_s }
    @auto_complete = proc do |s|
      command_list = @auto_complete_commands
      result = command_list.grep(/^#{Regexp.escape(s)}/)
      if result.nil? || result.empty?
        Readline::FILENAME_COMPLETION_PROC.call(s)
      else
        result
      end
    end
  end

  def handle(args)
    usage = "Usage: morpheus #{command_name}"
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      # change to a temporary home directory, delete it afterwards.
      opts.on('-e','--exec COMMAND', "Execute the provided morpheus commands and exit.") do |val|
        @execute_mode = true
        @execute_mode_command = val
      end
      opts.on('--norc','--norc', "Do not read and execute the personal initialization script .morpheusrc") do
        @norc = true
      end
      opts.on('-I','--insecure', "Allow for insecure HTTPS communication i.e. bad SSL certificate") do |val|
        @@insecure = true
        Morpheus::RestClient.enable_ssl_verification = false
      end
       opts.on('-Z','--incognito', "Incognito mode. Use a temporary shell, no saved credentials and no history.") do
        @incognito_mode = true
        #@norc = true # perhaps?
        tmpdir = ENV['MORPHEUS_CLI_TMPDIR'] || ENV['TMPDIR'] || ENV['TMP']
        if !tmpdir
          puts_error "Temporary directory not found. Use environment variable MORPHEUS_CLI_TMPDIR or TMPDIR or TMP"
        end
        @original_home_directory = my_terminal.home_directory
        @temporary_home_directory = File.join(tmpdir, "morpheus-temp-shell-#{rand().to_s[2..7]}")
        # change to a temporary home directory
        Morpheus::Logging::DarkPrinter.puts "incognito mode" if Morpheus::Logging.debug?
        Morpheus::Logging::DarkPrinter.puts "temporary home directory is #{@temporary_home_directory}" if Morpheus::Logging.debug?
        my_terminal.set_home_directory(@temporary_home_directory)
        # wow..this already has cached list of Remote.appliances
        # this is kinda nice though..keep it for now, 
        #Morpheus::Cli::Remote.load_appliance_file
        
        Morpheus::Cli::Remote.appliances.each do |app_name, app|
          #app[:username] = "(anonymous)"
          #app[:status] = "fresh"
          app[:authenticated] = false
          app.delete(:username)
          app.delete(:last_login_at)
          app.delete(:last_logout_at)
          app.delete(:last_success_at)
          app.delete(:last_check)
          app.delete(:username)
          app.delete(:error)
          #app[:error] = "ho ho ho"
        end
        
        # Morpheus::Cli::Remote.save_appliances(new_remote_config)

        # Morpheus::Cli::Remote.clear_active_appliance
        # Morpheus::Cli::Credentials.clear_saved_credentials(@appliance_name)
        # Morpheus::Cli::Credentials.load_saved_credentials
        # Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      end
      opts.on('-C','--nocolor', "Disable ANSI coloring") do
        Term::ANSIColor::coloring = false
      end
      opts.on('-V','--debug', "Print extra output for debugging.") do |json|
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end
      opts.on( '-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
    end
    optparse.parse!(args)

    @history_logger ||= load_history_logger rescue nil
    @history_logger.info "shell started" if @history_logger
    load_history_from_log_file()


    # execute startup script
    if !@norc
      if File.exists?(Morpheus::Cli::DotFile.morpheusrc_filename)
        @history_logger.info("load source #{Morpheus::Cli::DotFile.morpheusrc_filename}") if @history_logger
        Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheusrc_filename).execute()
      end
    end

    reinitialize()
    # recalculate_prompt()
    # recalculate_auto_complete_commands()

    result = nil
    if @execute_mode_command
      # execute a single command and exit
      result = execute(@execute_mode_command)
    else
      # interactive prompt
      result = 0
      @exit_now_please = false
      while !@exit_now_please do
        Readline.completion_append_character = " "
        Readline.completion_proc = @auto_complete
        Readline.basic_word_break_characters = ""
        #Readline.basic_word_break_characters = "\t\n\"\‘`@$><=;|&{( "
        input = Readline.readline(@calculated_prompt, true).to_s
        input = input.strip

        result = execute(input)
        print reset
      end
    end
    
    # incognito mode, cover our tracks
    if @temporary_home_directory
      if @temporary_home_directory.include?("morpheus-temp-shell")
        begin
          FileUtils.remove_dir(@temporary_home_directory, true)
          Morpheus::Logging::DarkPrinter.puts "cleaning up temporary home directory #{@temporary_home_directory}" if Morpheus::Logging.debug?
        rescue
        end
      end
      @temporary_home_directory = nil
      if @original_home_directory
        my_terminal.set_home_directory(@original_home_directory)
      end
      @original_home_directory = nil
    end

    return result
  end

  # return exitstatus integer for a given command result
  #todo: clean up CliCommand return values, handle a few diff types for now
  def parse_result_exitstatus(result)
    exit_code, err = 0, nil
    if result.is_a?(Array) # exit_code, err
      exit_code = result[0].to_i
      err = result[1]
    elsif result == nil || result == true || result == 0
      exit_code = 0
    elsif result == false
      exit_code = 1
    # elsif result.is_a?(Integer)
    #   exit_code = result.to_i
    else
      exit_code = result.to_i
    end
    # return exit_code, err
    return exit_code
  end

  # same as Terminal instance
  def execute(input)
    # args = Shellwords.shellsplit(input)
    #cmd = args.shift
    #execute_commands(input)
    result = execute_commands_as_expression(input)
    # skip logging of exit and !cmd
    unless input.strip.empty? || (["exit", "history"].include?(input.strip)) || input.strip[0].to_s.chr == "!"
      log_history_command(input.strip)
    end
    return result
  end

  def execute_commands_as_expression(input)
    flow = input
    if input.is_a?(String)
      begin
        flow = Morpheus::Cli::ExpressionParser.parse(input)
      rescue Morpheus::Cli::ExpressionParser::InvalidExpression => e
        @history_logger.error "#{e.message}" if @history_logger
        return Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) # lol
      end
    end
    final_command_result = nil
    if flow.size == 0
      # no input eh?
    else
      last_command_result = nil
      if ['&&','||', '|'].include?(flow.first)
        puts_error "#{Morpheus::Terminal.angry_prompt}invalid command format, begins with an operator: #{input}"
        return 99
      elsif ['&&','||', '|'].include?(flow.last)
        puts_error "#{Morpheus::Terminal.angry_prompt}invalid command format, ends with an operator: #{input}"
        return 99
      # elsif ['&&','||', '|'].include?(flow.last)
      #   puts_error "invalid command format, consecutive operators: #{cmd}"
      else
        #Morpheus::Logging::DarkPrinter.puts "Executing command flow: #{flow.inspect}" if Morpheus::Logging.debug?
        previous_command = nil
        previous_command_result = nil
        current_operator = nil
        still_executing = true
        flow.each do |flow_cmd|
          if still_executing
            if flow_cmd == '&&'
              # AND operator
              current_operator = flow_cmd
              if parse_result_exitstatus(previous_command_result) != 0
                still_executing = false
              end
            elsif flow_cmd == '||' # or with previous command
              current_operator = flow_cmd
              if parse_result_exitstatus(previous_command_result) == 0
                still_executing = false
              end
            elsif flow_cmd == '|' # or with previous command
              puts_error "The PIPE (|) operator is not yet supported =["
              previous_command_result = nil
              still_executing = false
              # or just continue?
            elsif flow_cmd.is_a?(Array)
              # this is a subexpression, execute it as such
              current_operator = nil
              previous_command_result = execute_commands_as_expression(flow_cmd)
            else # it's a command, not an operator
              current_operator = nil
              previous_command_result = execute_command(flow_cmd)
            end
            previous_command = flow_cmd
          else
            #Morpheus::Logging::DarkPrinter.puts "operator skipped command: #{flow_cmd}" if Morpheus::Logging.debug?
          end
          # previous_command = flow_cmd
        end
        final_command_result = previous_command_result
      end
    end
    return final_command_result
  end

  def execute_command(input)

    #Morpheus::Logging::DarkPrinter.puts "Shell command: #{input}"
    input = input.to_s.strip

    if !input.empty?

      if input == 'exit'
        #print cyan,"Goodbye\n",reset
        @history_logger.info "exit" if @history_logger
        @exit_now_please = true
        return 0
        #exit 0
      elsif input == 'help'

        #print_h1 "Morpheus Shell Help", [], white
        #print "\n"

        puts "You are in a morpheus client shell."
        puts "See the available commands below."


        puts "\nCommands:"
        # commands = @morpheus_commands + @shell_commands
        @morpheus_commands.sort.each {|cmd|
          puts "\t#{cmd.to_s}"
        }
        #puts "\n"
        puts "\nShell Commands:"
        @shell_commands.each {|cmd|
          puts "\t#{cmd.to_s}"
        }
        puts "\n"
        puts "For more information, see https://github.com/gomorpheus/morpheus-cli/wiki"
        #print "\n"
        return 0
      elsif input =~ /^\s*#/
        Morpheus::Logging::DarkPrinter.puts "ignored comment: #{input}" if Morpheus::Logging.debug?
        return 0
      # this is a full blown command now
      # elsif input =~ /^sleep/
      #   sleep_sec = input.sub("sleep ", "").to_f
      #   if (!(sleep_sec > 0))
      #     # raise_command_error "sleep requires the argument [seconds]. eg. sleep 3.14"
      #     puts_error  "sleep requires argument [seconds]. eg. sleep 3.14"
      #     return false
      #   end
      #   log_history_command(input)
      #   Morpheus::Logging::DarkPrinter.puts "sleeping for #{sleep_sec}s ... zzzZzzzZ" if Morpheus::Logging.debug?
      #   begin
      #     sleep(sleep_sec)
      #   rescue Interrupt
      #     Morpheus::Logging::DarkPrinter.puts "\nInterrupt. waking up from sleep early"
      #   end
      #   return 0
      elsif input =~ /^history/
        n_commands = input.sub(/^history\s?/, '').sub(/\-n\s?/, '')
        n_commands = n_commands.empty? ? 25 : n_commands.to_i
        cmd_numbers = @history.keys.last(n_commands)
        if cmd_numbers.size == 1
          puts "Last command"
        else
          puts "Last #{cmd_numbers.size} commands"
        end
        cmd_numbers.each do |cmd_number|
          cmd = @history[cmd_number]
          puts "#{cmd_number.to_s.rjust(3, ' ')}  #{cmd}"
        end
        last_cmd = cmd_numbers.last ? @history[cmd_numbers.last] : nil
        if input != last_cmd # no consecutive
          log_history_command(input)
        end
        return 0
      elsif input == 'clear'
        print "\e[H\e[2J"
        return 0
      elsif input == 'flush-history' || input == 'flush_history'
        file_path = history_file_path
        if File.exists?(file_path)
          File.truncate(file_path, 0)
        end
        @history = {}
        @last_command_number = 0
        @history_logger = load_history_logger
        puts "history cleared!"
        return 0
      # elsif input == "edit rc"
      #   fn = Morpheus::Cli::DotFile.morpheusrc_filename
      #   editor = ENV['EDITOR'] # || 'nano'
      #   if !editor
      #     puts "You have no EDITOR defined. Use 'export EDITOR=emacs'"
      #     #puts "Trying nano..."
      #     #editor = "nano"
      #   end
      #   system("which #{editor} > /dev/null 2>&1")
      #   has_editor = $?.success?
      #   if has_editor
      #     puts "opening #{fn} for editing with #{editor} ..."
      #     system("#{editor} #{fn}")
      #     puts "Use 'reload' to re-execute your startup script #{File.basename(fn)}"
      #   else
      #     puts_error2 Morpheus::Terminal.angry_prompt
      #     puts_error "The defined EDITOR '#{editor}' was not found on your system."
      #   end
      #   return 0 # $?
      # elsif input == "edit profile"
      #   fn = Morpheus::Cli::DotFile.morpheus_profile_filename
      #   editor = ENV['EDITOR'] # || 'nano'
      #   if !editor
      #     puts "You have no EDITOR defined. Use 'export EDITOR=emacs'."
      #     #puts "Trying nano..."
      #     #editor = "nano"
      #   end
      #   system("which #{editor} > /dev/null 2>&1")
      #   has_editor = $?.success?
      #   if has_editor
      #     puts "opening #{fn} for editing with #{editor} ..."
      #     `#{editor} #{fn}`
      #     puts "Use 'reload' to re-execute your startup script #{File.basename(fn)}"
      #   else
      #     puts_error Morpheus::Terminal.angry_prompt
      #     puts_error "The defined EDITOR '#{editor}' was not found on your system."
      #   end
      #   return 0 # $?
      elsif input == 'reload' || input == 'reload!'
        # raise RestartShellPlease
        #log_history_command(input)
        # could just fork instead?
        # clear registry
        Morpheus::Cli::CliRegistry.instance.flush
        # reload code
        Morpheus::Cli.load!

        # raise RestartShellPlease

        # execute startup scripts
        if File.exists?(Morpheus::Cli::DotFile.morpheus_profile_filename)
          Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheus_profile_filename).execute()
        end
        if File.exists?(Morpheus::Cli::DotFile.morpheusrc_filename)
          Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheusrc_filename).execute()
        end
        
        # recalculate shell environment
        reinitialize()

        Morpheus::Logging::DarkPrinter.puts "shell has been reloaded" if Morpheus::Logging.debug?
        return 0
      elsif input == '!!'
        cmd_number = @history.keys[-1]
        input = @history[cmd_number]
        if !input
          puts "There is no previous command"
          return false
        end
        return execute(input)
      elsif input =~ /^\!.+/
        cmd_number = input.sub("!", "").to_i
        if cmd_number != 0
          old_input = @history[cmd_number]
          if !old_input
            puts "Command not found by number #{cmd_number}"
            return 0
          end
          #puts "executing history command: (#{cmd_number}) #{old_input}"
          # log_history_command(old_input)
          # remove this from readline, and replace it with the old command
          Readline::HISTORY.pop
          Readline::HISTORY << old_input
          return execute(old_input)
        end

      elsif input == "insecure"
        Morpheus::RestClient.enable_ssl_verification = false
        return 0

      # use log-level [debug|info]
      # elsif input =~ /^log_level/ # hidden for now
      #   log_level = input.sub(/^log_level\s*/, '').strip
      #   if log_level == ""
      #     puts "#{Morpheus::Logging.log_level}"
      elsif input == "debug"
        log_history_command(input)
        return Morpheus::Cli::LogLevelCommand.new.handle(["debug"])
      elsif ["hello","hi","hey","hola"].include?(input.strip.downcase)
        print "#{input.capitalize}, how may I #{cyan}help#{reset} you?\n"
        return 0
      elsif input == "shell"
        print "#{cyan}You are already in a shell.#{reset}\n"
        return false
      elsif input =~ /^\.\s/
        # dot alias for source <file>
        log_history_command(input)
        return Morpheus::Cli::SourceCommand.new.handle(input.split[1..-1])
      end
      cmd_result = nil
      unless input =~ /log-level/
        @return_to_log_level = Morpheus::Logging.log_level
      end
      unless input =~ /coloring/
        @return_to_coloring = Term::ANSIColor::coloring?
      end
      begin
        argv = Shellwords.shellsplit(input)
        cmd_name = argv[0]
        cmd_args = argv[1..-1]
        if Morpheus::Cli::CliRegistry.has_command?(cmd_name) || Morpheus::Cli::CliRegistry.has_alias?(cmd_name)
          #log_history_command(input)
          cmd_result = Morpheus::Cli::CliRegistry.exec(cmd_name, cmd_args)
        else
          puts_error "#{Morpheus::Terminal.angry_prompt}'#{cmd_name}' is not a morpheus command. Use 'help' to see the list of available commands."
          @history_logger.warn "Unrecognized Command #{cmd_name}" if @history_logger
          cmd_result = -1
        end
      rescue Interrupt
        # nothing to do
        @history_logger.warn "shell interrupt" if @history_logger
        print "\nInterrupt. aborting command '#{input}'\n"
      rescue SystemExit => cmdexit
        # nothing to do
        # print "\n"
        cmd_result = cmdexit.status
      rescue => e
        @history_logger.error "#{e.message}" if @history_logger
        cmd_result = Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) # lol
        # exit 1
      ensure
        if @return_to_log_level
          Morpheus::Logging.set_log_level(@return_to_log_level)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
          @return_to_log_level = nil
        end
        if @return_to_coloring != nil
          Term::ANSIColor::coloring = @return_to_coloring
          @return_to_coloring = nil
        end
      end

      # commands should be a number or nil (treated as 0)
      if cmd_result == true
        cmd_result = 0
      end
      return cmd_result
    end

  end

  def get_prompt

    # print cyan,"morpheus > ",reset
    # input = $stdin.gets.chomp!

    input = ''
    while char=$stdin.getch do
      if char == '\n'
        print "\r\n"
        puts "executing..."
        break
      end
      print char
      input << char
    end
    return input
  end

  def history_file_path
    File.join(Morpheus::Cli.home_directory, "shell_history")
  end

  def load_history_logger
    file_path = history_file_path
    if !Dir.exists?(File.dirname(file_path))
      FileUtils.mkdir_p(File.dirname(file_path))
    end
    if !File.exists?(file_path)
      FileUtils.touch(file_path)
      FileUtils.chmod(0600, file_path)
    end
    logger = Logger.new(file_path)
    # logger.formatter = proc do |severity, datetime, progname, msg|
    #   "#{msg}\n"
    # end
    return logger
  end

  def load_history_from_log_file(n_commands=1000)
    @history ||= {}
    @last_command_number ||= 0

    begin
      if Gem.win_platform?
        return @history
      end
      file_path = history_file_path
      FileUtils.mkdir_p(File.dirname(file_path))
      # grab extra lines because not all log entries are commands
      n_lines = n_commands + 500
      history_lines = `tail -n #{n_lines} #{file_path}`.split(/\n/)
      command_lines = history_lines.select do |line|
        line.match(/\(cmd (\d+)\) (.+)/)
      end
      command_lines = command_lines.last(n_commands)
      command_lines.each do |line|
        matches = line.match(/\(cmd (\d+)\) (.+)/)
        if matches && matches.size == 3
          cmd_number = matches[1].to_i
          cmd = matches[2]

          @last_command_number = cmd_number
          @history[@last_command_number] = cmd

          # for Ctrl+R history searching
          Readline::HISTORY << cmd
        end
      end
    rescue => e
      # raise e
      # puts "failed to load history from log"
      @history = {}
    end
    return @history
  end

  def log_history_command(cmd)
    @history ||= {}
    @last_command_number ||= 0
    @last_command_number += 1
    @history[@last_command_number] = cmd
    if @history_logger
      @history_logger.info "#{@current_username}@#{@appliance_name} : -- : (cmd #{@last_command_number}) #{cmd}"
    end
  end
end
