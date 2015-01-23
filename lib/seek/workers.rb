require 'delayed/command'

#module for handling interaction with delayed job workers
module Seek
  module Workers
    def self.start number=0,restart=false
      number = Seek::Config.workflows_enabled ? number : 0

      action = restart ? "restart" : "start"

      commands =
          ["--queue=#{Delayed::Worker.default_queue_name} -i #{number} #{action}"]
      if Seek::Config.auth_lookup_enabled
        commands << "--queue=#{AuthLookupUpdateJob.job_queue_name} -i #{number+1} #{action}"
      end
      if number > 0
        commands << "--queue=#{TavernaPlayer.job_queue_name} -n #{number} #{action}"
      end

      begin
        commands.map { |c| Delayed::Command.new(c.split).daemonize }
      rescue SystemExit
      end
    end

    def self.stop
      begin
        Delayed::Command.new(["stop"]).daemonize
      rescue SystemExit
      end
    end

    def self.status
      begin
        Delayed::Command.new(["status"]).daemonize
      rescue SystemExit
      end
    end

    def self.restart number=0
      self.start(number,true)
    end
  end
end