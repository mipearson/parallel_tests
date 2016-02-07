require 'parallel_tests'
require 'parallel_tests/rspec/logger_base'

class ParallelTests::RSpec::RuntimeLogger < ParallelTests::RSpec::LoggerBase
  def initialize(*args)
    super
    @example_times = Hash.new(0)
    @example_process_times = {}
    @group_nesting = 0 unless RSPEC_1
  end

  if RSPEC_3
    RSpec::Core::Formatters.register self, :example_group_started, :example_group_finished, :start_dump
  end

  if RSPEC_1
    def example_started(*args)
      @time = ParallelTests.now
      super
    end

    def example_passed(example)
      file = example.location.split(':').first
      @example_times[file] += ParallelTests.now - @time
      super
    end
  else
    def example_group_started(example_group)
      @time = ParallelTests.now if @group_nesting == 0
      @ptime = Process.times if @group_nesting == 0

      @group_nesting += 1
      super
    end

    def example_group_finished(notification)
      @group_nesting -= 1
      if @group_nesting == 0
        path = (RSPEC_3 ? notification.group.file_path : notification.file_path)
        @example_times[path] += ParallelTests.now - @time
        now = Process.times
        @example_process_times[path] ||= [0,0,0,0]
        @example_process_times[path][0] += now.utime - @ptime.utime
        @example_process_times[path][1] += now.stime - @ptime.stime
        @example_process_times[path][2] += now.cutime - @ptime.cutime
        @example_process_times[path][3] += now.cstime - @ptime.cstime
      end
      super if defined?(super)
    end
  end

  def dump_summary(*args);end
  def dump_failures(*args);end
  def dump_failure(*args);end
  def dump_pending(*args);end

  def start_dump(*args)
    return unless ENV['TEST_ENV_NUMBER'] #only record when running in parallel
    # TODO: Figure out why sometimes time can be less than 0
    lock_output do
      @example_times.each do |file, time|
        relative_path = file.sub(/^#{Regexp.escape Dir.pwd}\//,'').sub(/^\.\//, "")
        ptime = @example_process_times[file]
        total = ptime[0] + ptime[1] + ptime[2] + ptime[3]
        @output.puts "#{relative_path}:#{time > 0 ? time : 0} #{total} #{ptime.join(' ')}"
      end
    end
    @output.flush
  end
end
