# frozen_string_literal: true

require_relative "data_drip/version"
require "rails"
require "active_model"
require "data_drip/engine"
require "data_drip/backfill"

module DataDrip
  mattr_accessor :backfiller_class, default: "::User"
  mattr_accessor :backfiller_name_attribute, default: :name
  mattr_accessor :current_backfiller_method, default: :current_user
  mattr_accessor :base_controller_class, default: "::ApplicationController"
  mattr_accessor :importmap, default: Importmap::Map.new
  mattr_accessor :before_backfill, default: nil
  mattr_accessor :sleep_time, default: 0.1

  class Error < StandardError
  end

  def self.all
    DataDrip::Backfill.descendants.uniq
  end

  def self.cross_rails_enum(klass, name, values)
    if Rails::VERSION::MAJOR >= 8
      klass.enum name, values
    else
      klass.enum name => values
    end
  end
end
