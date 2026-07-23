class AlwaysFails < DataDrip::Script
  description "A script that always raises, used to exercise failure handling."

  input :message, :string, default: "boom"

  def call
    log "about to fail"
    raise StandardError, message
  end
end
