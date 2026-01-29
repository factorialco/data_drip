class HookNotifier
  include Singleton

  attr_accessor :hooks

  def initialize
    @hooks = {}
  end

  def set(key, value)
    @hooks[key] = value
  end

  def get(key)
    @hooks[key]
  end

  def empty?
    @hooks.empty?
  end

  def clear
    @hooks = {}
  end
end
