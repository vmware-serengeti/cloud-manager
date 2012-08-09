###############################################################################
#    Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
################################################################################

# @since serengeti 0.5.0
# @version 0.5.0

module Serengeti
  module CloudManager
    module Parallel
      def map_each_by_threads(map, options={})
        group_each_by_threads(map.values, options) { |item| yield item }
      end

      def group_each_by_threads(group, options={})
        work_thread = []
        if options[:order] || group.size <= 1
          #serial method
          logger.debug("#{options[:callee]} run in serial model")
          group.each { |item| yield item }
        else
          #paralleled method for multi-work
          logger.debug("#{options[:callee]} run in paralleled model")
          action_msg = Thread.current[:action]
          group.each do |item|
            work_thread << Thread.new(item) do |item|
              begin
                Thread.current[:thread_callee] = options[:callee]
                Thread.current[:action] = action_msg
                yield item
              rescue => e
                logger.error("#{options[:callee]} threads failed #{e} - #{e.backtrace.join("\n")}")
              end
              Thread.current[:thread_callee] = ''
            end
          end
          logger.debug("Created #{work_thread.size} threads to work for #{group.size} jobs")
          work_thread.each { |t| t.join }
        end
        logger.debug("Finish group operation for #{options[:callee]}")
      end

      def vm_deploy_group_pool(thread_pool, group, options={})
        thread_pool.wrap do |pool|
          group.each do |vm|
            logger.debug("enter : #{vm.pretty_inspect}")
            pool.process do
              begin
                yield(vm)
              rescue
                #TODO do some warning handler here
                raise
              end
            end
            logger.info("##Finish change one vm_group")
          end
        end
      end

      class ThreadPool
        def initialize(options = {})
          @actions = []
          @lock = Mutex.new
          @cv = ConditionVariable.new
          @max_threads = options[:max_threads] || 1
          @available_threads = @max_threads

          logger = Serengeti::CloudManager.logger
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
                logger.debug("Creating new thread")
                @available_threads -= 1
                create_thread
              else
                logger.debug("All threads are currently busy, queuing action")
              end
            elsif @state == :paused
              logger.debug("Pool is paused, queueing action.")
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
                    logger.debug("Found an action that needs to be processed")
                  else
                    logger.debug("Thread is no longer needed, cleaning up")
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
            logger.debug("Worker thread raised exception: #{exception} - #{exception.backtrace.join("\n")}")
          else
            logger.debug("Worker thread raised exception: #{exception}")
          end
          @lock.synchronize do
            @boom = exception if @boom.nil?
          end
        end

        def working?
          @boom.nil? && (@available_threads != @max_threads || !@actions.empty?)
        end

        def wait
          logger.debug("Waiting for tasks to complete")
          @lock.synchronize do
            @cv.wait(@lock) while working?
            raise @boom if @boom
          end
        end

        def shutdown
          return if @state == :closed
          logger.debug("Shutting down pool")
          @lock.synchronize do
            return if @state == :closed
            @state = :closed
            @actions.clear
          end
          @threads.each { |t| t.join }
        end

      end

    end

    class Config
      def_const_value :vm_name_split_sign, '-'
    end

    module Utils
      def parse_vm_from_name(vm_name, options={})
        #result = /([\w\s\d]+)#{config.vm_name_split_sign}([\w\s\d]+)#{config.vm_name_split_sign}([\d]+)/.match(vm_name)
	result = vm_name.split(config.vm_name_split_sign)
	ret = Hash.new

	raise "#{vm_name} is invalid!" unless result
	if result[0]
	  return nil unless (result[0] =~ /[\w\s\d]+/)
	  ret["cluster_name"] = result[0]
	end
        if result[1]
	  return nil unless (result[1] =~ /[\w\s\d]+/)
	  ret["group_name"] = result[1]
	end
        if result[2]
	  return nil unless (result[2] =~ /[\d]+/)
	  ret["num"] = result[2]
	end
	ret
      end

      def gen_cluster_vm_name(group_name, num)
	[config.serengeti_cluster_name, group_name, num].compact.join(config.vm_name_split_sign)
      end

      def gen_disk_name(datastore, vm, type, unit_number)
        "[#{datastore.name}] #{vm.name}/#{type}-disk-#{unit_number}.vmdk"
      end

      def vm_match_targets?(vm_name, targets)
	logger.debug("vm:#{vm_name} match?")
	targets.each{ |target|
	    return true if vm_match_one_target?(vm_name, target)
	}
	false
      end

      def vm_match_one_target?(vm_name, target)
	target_info = parse_vm_from_name(target)
	vm_info = parse_vm_from_name(vm_name)
	return false unless vm_info
	return false if (target_info["cluster_name"] != config.serengeti_cluster_name  || vm_info["cluster_name"] != target_info["cluster_name"])
	return false if (target_info["group_name"] && vm_info["group_name"] != target_info["group_name"])
	return false if (target_info["num"] && vm_info["num"] != target_info["num"])
	logger.debug("vm:#{vm_name} match: #{target}")
	true
      end

      def vm_is_this_cluster?(vm_name)
        logger.debug("vm:#{vm_name} is in cluster?")
        result = parse_vm_from_name(vm_name)
        return false unless result
        return false unless (result["cluster_name"] == config.serengeti_cluster_name)

        logger.debug("vm:#{vm_name} is in cluster:#{config.serengeti_cluster_name}")
        true
      end
   end

    class Cloud
      def create_plugin_obj(plugin, parameter = nil)
        begin
          logger.debug("#{plugin.pretty_inspect}")
          require_file, = plugin['require']
          plugin_name = plugin['obj']

          logger.debug("require_file:#{require_file}, plugin_name:#{plugin_name}")
          eval("require \'#{require_file}\'") if require_file.to_s.size > 0

          return eval(plugin_name).new(parameter)
        rescue => e
          logger.error("Create plugin failed.\n #{e} - #{e.backtrace.join("\n")}")
          raise PluginException,"Do not support #{plugin_name} plugin in file:#{require_file}!"
        end
      end

      def create_service_obj(plugin, parameter = nil)
        create_plugin_obj(plugin, parameter)
      end

    end

  end
end

