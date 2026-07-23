# frozen_string_literal: true

require_relative "data_drip/version"
require "digest"
require "rails"
require "active_model"
require "data_drip/engine"
require "data_drip/types/enum"
require "data_drip/concerns/schematized_options"
require "data_drip/backfill"
require "data_drip/script"

module DataDrip
  mattr_accessor :backfiller_class, default: "::User"
  mattr_accessor :backfiller_name_attribute, default: :name
  mattr_accessor :current_backfiller_method, default: :current_user
  mattr_accessor :base_controller_class, default: "::ApplicationController"
  mattr_accessor :base_job_class, default: "ActiveJob::Base"
  mattr_accessor :queue_name, default: (ENV["DATA_DRIP_QUEUE"].presence || "data_drip").to_sym
  mattr_accessor :child_queue_name, default: (ENV["DATA_DRIP_CHILD_QUEUE"].presence || "data_drip_child").to_sym
  mattr_accessor :importmap, default: Importmap::Map.new
  mattr_accessor :before_backfill, default: nil
  mattr_accessor :sleep_time, default: 5
  mattr_accessor :hooks_handler_class_name, default: nil

  class Error < StandardError
  end

  def self.hooks_handler_class
    return nil unless hooks_handler_class_name.present?

    hooks_handler_class_name.safe_constantize
  end

  # The engine ships fully-compiled, self-contained Tailwind CSS. It is served
  # directly by DataDrip::AssetsController (see config/routes.rb) rather than
  # through the host's asset pipeline: the compiled output uses modern CSS
  # (`@import "tailwindcss"` in the source, cascade layers, `oklch()`, media
  # query range syntax) that a libsass/SassC-based Sprockets pipeline cannot
  # parse or recompress. Reading it here keeps the engine independent of
  # whatever asset toolchain (Sprockets, Propshaft, none) the host runs.
  def self.compiled_css_file
    Engine.root.join("app/assets/stylesheets/data_drip/tailwind.css")
  end

  def self.compiled_css
    refresh_compiled_css
    @compiled_css
  end

  # Cache-busting fingerprint for the stylesheet URL and its ETag. Derived from
  # the CSS itself so it changes whenever the compiled output does, without
  # depending on a VERSION bump.
  def self.compiled_css_digest
    refresh_compiled_css
    @compiled_css_digest
  end

  # Read the compiled CSS once and keep it in memory. The gem's `lib` is not
  # code-reloaded, so a plain memo would go stale under `bin/dev`'s Tailwind
  # watch; keying on the file's mtime means production reads exactly once (the
  # shipped file never changes) while local development picks up recompiles.
  def self.refresh_compiled_css
    mtime = compiled_css_file.mtime
    return if defined?(@compiled_css_mtime) && @compiled_css_mtime == mtime

    css = compiled_css_file.read.freeze
    @compiled_css = css
    @compiled_css_digest = Digest::SHA256.hexdigest(css)[0, 12].freeze
    @compiled_css_mtime = mtime
  end
  private_class_method :refresh_compiled_css

  def self.all
    DataDrip::Backfill.descendants.uniq
  end

  def self.scripts
    DataDrip::Script.descendants.uniq
  end

  def self.cross_rails_enum(klass, name, values)
    if Rails::VERSION::MAJOR >= 8
      klass.enum name, values
    else
      klass.enum name => values
    end
  end
end
