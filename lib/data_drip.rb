# frozen_string_literal: true

require_relative "data_drip/version"
require 'data_drip/engine'
require 'data_drip/backfill'

module DataDrip
  class Error < StandardError; end

  def self.all
    DataDrip::Backfill.descendants.uniq
  end
end

