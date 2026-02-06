# frozen_string_literal: true

module DataDrip
  module Hookable
    private

    def run_status_change_hooks
      return unless status_previously_changed?

      if @__hooks_ran_for_status_change
        @__hooks_ran_for_status_change = false
        return
      end

      run_hook(:before, status)
      run_around_hook(status) {}
      run_hook(:after, status)
    end

    def with_action_hooks(status_value)
      return yield if @__hooks_in_action

      @__hooks_in_action = true
      run_hook(:before, status_value)
      run_around_hook(status_value) do
        @__hooks_ran_for_status_change = true
        yield
      end
      run_hook(:after, status_value)
    ensure
      @__hooks_in_action = false
    end

    def run_hook(timing, status_value)
      hook_name = "#{timing}_#{hook_prefix}_#{status_value}"
      hook_target_for(hook_name)&.public_send(hook_name, self)
    end

    def run_around_hook(status_value)
      hook_name = "around_#{hook_prefix}_#{status_value}"
      hook_target = hook_target_for(hook_name)

      if hook_target
        hook_target.public_send(hook_name, self) { yield }
      else
        yield
      end
    end

    def hook_prefix
      raise NotImplementedError
    end

    def hook_target_for(_hook_name)
      raise NotImplementedError
    end
  end
end
