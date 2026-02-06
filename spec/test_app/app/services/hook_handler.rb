class HookHandler
  def self.before_run_enqueued(run)
    sequence = HookNotifier.instance.get("handler_run_enqueued_sequence") || []
    sequence << "before"
    HookNotifier.instance.set("handler_run_enqueued_sequence", sequence)
    HookNotifier.instance.set("handler_before_run_enqueued", run.id)
  end

  def self.around_run_enqueued(run)
    sequence = HookNotifier.instance.get("handler_run_enqueued_sequence") || []
    sequence << "around_before"
    HookNotifier.instance.set("handler_run_enqueued_sequence", sequence)
    yield
    sequence = HookNotifier.instance.get("handler_run_enqueued_sequence") || []
    sequence << "around_after"
    HookNotifier.instance.set("handler_run_enqueued_sequence", sequence)
  end

  def self.after_run_enqueued(run)
    sequence = HookNotifier.instance.get("handler_run_enqueued_sequence") || []
    sequence << "after"
    HookNotifier.instance.set("handler_run_enqueued_sequence", sequence)
  end

  def self.after_run_completed(run)
    HookNotifier.instance.set("handler_after_run_completed", run.id)
  end

  def self.after_batch_enqueued(batch)
    HookNotifier.instance.set("handler_after_batch_enqueued", batch.id)
  end

  def self.after_batch_completed(batch)
    HookNotifier.instance.set("handler_after_batch_completed", batch.id)
  end

  def self.before_batch_running(batch)
    sequence = HookNotifier.instance.get("handler_batch_running_sequence") || []
    sequence << "before"
    HookNotifier.instance.set("handler_batch_running_sequence", sequence)
  end

  def self.around_batch_running(batch)
    sequence = HookNotifier.instance.get("handler_batch_running_sequence") || []
    sequence << "around_before"
    HookNotifier.instance.set("handler_batch_running_sequence", sequence)
    yield
    sequence = HookNotifier.instance.get("handler_batch_running_sequence") || []
    sequence << "around_after"
    HookNotifier.instance.set("handler_batch_running_sequence", sequence)
  end

  def self.after_batch_running(batch)
    sequence = HookNotifier.instance.get("handler_batch_running_sequence") || []
    sequence << "after"
    HookNotifier.instance.set("handler_batch_running_sequence", sequence)
  end
end
