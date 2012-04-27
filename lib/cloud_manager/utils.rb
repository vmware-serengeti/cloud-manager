module VHelper::CloudManager
  module Parallel
    def map_each_by_threads(map, options={})
      group_each_by_threads(map.values, options) { |item| yield item }
    end

    def group_each_by_threads(group, options={})
      work_thread = []
      group.each { |item|
        work_thread << Thread.new(item) { |item|
          begin
            yield item
          rescue => e
            @logger.debug("#{options[:callee]} threads failed")
            @logger.debug("#{e} - #{e.backtrace.join("\n")}")
          end
        }
      }
      work_thread.each { |t| t.join }
      @logger.info("##Finish #{options[:callee]}")
    end

    class ThreadPool
      def initialize(options = {})
        @actions = []
        @lock = Mutex.new
        @cv = ConditionVariable.new
        @max_threads = options[:max_threads] || 1
        @available_threads = @max_threads
        @logger = options[:logger]
        @boom = nil
        @original_thread = Thread.current
        @threads = []
        @state = :open
      end

      def wrap
        begin
          yield self
          wait
        ensure
          shutdown
        end
      end

      def pause
        @lock.synchronize do
          @state = :paused
        end
      end

      def resume
        @lock.synchronize do
          @state = :open
          [@available_threads, @actions.size].min.times do
            @available_threads -= 1
            create_thread
          end
        end
      end

      def process(&block)
        @lock.synchronize do
          @actions << block
          if @state == :open
            if @available_threads > 0
              @logger.debug("Creating new thread")
              @available_threads -= 1
              create_thread
            else
              @logger.debug("All threads are currently busy, queuing action")
            end
          elsif @state == :paused
            @logger.debug("Pool is paused, queueing action.")
          end
        end
      end

      def create_thread
        thread = Thread.new do
          begin
            loop do
              action = nil
              @lock.synchronize do
                action = @actions.shift unless @boom
                if action
                  @logger.debug("Found an action that needs to be processed")
                else
                  @logger.debug("Thread is no longer needed, cleaning up")
                  @available_threads += 1
                  @threads.delete(thread) if @state == :open
                end
              end

              break unless action

              begin
                action.call
              rescue Exception => e
                raise_worker_exception(e)
              end
            end
          end
          @lock.synchronize { @cv.signal unless working? }
        end
        @threads << thread
      end

      def raise_worker_exception(exception)
        if exception.respond_to?(:backtrace)
          @logger.debug("Worker thread raised exception: #{exception} - #{exception.backtrace.join("\n")}")
        else
          @logger.debug("Worker thread raised exception: #{exception}")
        end
        @lock.synchronize do
          @boom = exception if @boom.nil?
        end
      end

      def working?
        @boom.nil? && (@available_threads != @max_threads || !@actions.empty?)
      end

      def wait
        @logger.debug("Waiting for tasks to complete")
        @lock.synchronize do
          @cv.wait(@lock) while working?
          raise @boom if @boom
        end
      end

      def shutdown
        return if @state == :closed
        @logger.debug("Shutting down pool")
        @lock.synchronize do
          return if @state == :closed
          @state = :closed
          @actions.clear
        end
        @threads.each { |t| t.join }
      end

    end

  end


  class VHelperCloud
    VM_SPLIT_SIGN = '-'
    def gen_vm_name(cluster_name, group_name, num)
      return "#{cluster_name}#{VM_SPLIT_SIGN}#{group_name}#{VM_SPLIT_SIGN}#{num}"
    end

    def vm_is_this_cluster?(vm_name)
      result = get_from_vm_name(vm_name)
      return false unless result
      return false unless (result[1] == @cluster_name)
      true
    end

    def get_from_vm_name(vm_name, options={})
      return /([\w\s\d]+)#{VM_SPLIT_SIGN}([\w\s\d]+)#{VM_SPLIT_SIGN}([\d]+)/.match(vm_name)
    end

    def self.Logger
      @@self_logger = Logger.new if @@self_logger.nil?
      @@self_logger
    end
  end

  class Logger
    def initialize()
      puts "initiated logger"
    end
    def info(msg)
      puts ("INFO: #{msg2str(msg)}")
    end

    def debug(msg)
      puts ("DEBUG: #{msg2str(msg)}")
    end

    def inspect; "<Cloud-manager-Logger>" end

    def msg2str(msg)
      case msg
      when ::String
        msg
      when ::Exception
        "EXCEPTION #{ msg.message } (#{ msg.class })\n" <<
        (msg.backtrace || []).join("\n")
      else
        msg.inspect
      end
    end
  end


end

