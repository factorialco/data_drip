class HookHandler
  def self.on_run_completed(run)
    puts 'on_run_completed'
  end

  def self.on_run_enqueued(run)
    puts 'on_run_enqueued'
  end
end
