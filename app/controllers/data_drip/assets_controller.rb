# frozen_string_literal: true

module DataDrip
  # Serves the engine's compiled Tailwind stylesheet straight from disk,
  # deliberately bypassing the host's asset pipeline. The compiled CSS is
  # modern (cascade layers, `oklch()`, media query range syntax) and cannot
  # survive a libsass/SassC Sprockets pipeline, which recompresses every CSS
  # asset through SassC. See DataDrip.compiled_css for the full rationale.
  #
  # Inherits from ActionController::Base rather than the host's configurable
  # base controller: the stylesheet carries no tenant data, so it needs no
  # authentication and must always be loadable, even before a host redirects
  # an unauthenticated request elsewhere.
  class AssetsController < ActionController::Base
    def stylesheet
      expires_in 1.year, public: true

      return unless stale?(etag: DataDrip.compiled_css_digest, public: true)

      render body: DataDrip.compiled_css, content_type: "text/css"
    end
  end
end
