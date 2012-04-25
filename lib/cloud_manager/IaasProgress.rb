module VHelper::CloudManager
  class IaasProcess
    attr_accessor :cluster_name
    attr_accessor :progress
    attr_accessor :result
    attr_accessor :finished
    attr_accessor :status
    def initialize
      @progress = 0
      @finished = false
      @status = "birth"
      @result = ""
    end
    def finished? ;@finished end
    def inspect
      "#{@progress}%, finished ? #{@finished?'yes':'no'}, status:#{@status}, servers:\n#{result.inspect}"
    end
  end
end

