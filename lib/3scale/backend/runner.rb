require 'optparse'

module ThreeScale
  module Backend
    module Runner
      extend self

      DEFAULT_OPTIONS = {:host => '0.0.0.0', :port => 3000}
      COMMANDS = [:start, :stop, :restart, :restore_backup, :archive]

      def run
        send(*parse!(ARGV))
      end

      def start(options)
        Server.start(options)
      end

      def stop(options)
        Server.stop(options)
      end

      def restart(options)
        Server.restart(options)
      end

      def restore_backup(options)
        puts ">> Replaying write commands from backup."
        Storage.instance(true).restore_backup
        puts ">> Done."
      end

      def archive(options)
        Archiver.store(:tag => `hostname`.strip)
        Archiver.cleanup
      end
      
      private

      def parse!(argv)
        options = DEFAULT_OPTIONS

        parser = OptionParser.new do |parser|
          parser.banner = 'Usage: 3scale_backend [options] command'
          parser.separator ""
          parser.separator "Options:"
        
          parser.on('-a', '--address HOST', 'bind to HOST address (default: 0.0.0.0)') { |value| options[:host] = value }
          parser.on('-p', '--port PORT',    'use PORT (default: 3000)')                { |value| options[:port] = value.to_i }
          parser.on('-d', '--daemonize',    'run as daemon')                           { |value| options[:daemonize] = true }
          parser.on('-l', '--log FILE' ,    'log file')                                { |value| options[:log_file] = value }

          parser.separator ""
          parser.separator "Commands: #{COMMANDS.join(', ')}"
        
          parser.parse!
        end

        command = argv.shift
        command &&= command.to_sym
        
        unless COMMANDS.include?(command)
          if command
            abort "Unknown command: #{command}. Use one of: #{COMMANDS.join(', ')}"
          else
            abort parser.to_s
          end
        end

        [command, options]
      end
    end
  end
end
