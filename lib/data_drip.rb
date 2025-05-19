# frozen_string_literal: true

require_relative "data_drip/version"
require 'data_drip/engine'
require 'data_drip/backfill'
require 'data_drip/hello'

module DataDrip
  class Error < StandardError; end
end

