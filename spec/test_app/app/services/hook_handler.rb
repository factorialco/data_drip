class HookHandler
  def self.on_run_completed(run)
    puts "on_run_completed"
  end

  def self.on_run_enqueued(run)
    puts "on_run_enqueued"
  end

  def self.on_batch_enqueued(batch)
    puts "on_batch_enqueued"
  end

  def self.on_batch_completed(batch)
    puts "on_batch_completed"
  end
end
