# frozen_string_literal: true

require_relative "data_drip/version"
require "rails"
require "data_drip/engine"
require "data_drip/backfill"

module DataDrip
  mattr_accessor :backfiller_class, default: "::User"
  mattr_accessor :backfiller_name_attribute, default: :name
  mattr_accessor :base_controller_class, default: "::ApplicationController"
  mattr_accessor :importmap, default: Importmap::Map.new

  class Error < StandardError
  end

  def self.all
    DataDrip::Backfill.descendants.uniq
  end
end
