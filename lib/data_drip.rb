# frozen_string_literal: true

require_relative "data_drip/version"
require "rails"
require "data_drip/engine"
require "data_drip/backfill"
# require_relative "../app/controllers/data_drip/backfill_runs_controller"

module DataDrip
  class Error < StandardError; end

  def self.all
    DataDrip::Backfill.descendants.uniq
  end
end
