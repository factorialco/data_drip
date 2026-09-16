# frozen_string_literal: true

require "spec_helper"

# Regression coverage for the stylesheet delivery path. The engine ships
# fully-compiled Tailwind CSS and must serve it *outside* the host asset
# pipeline: a libsass/SassC-based Sprockets host recompresses every CSS asset
# through SassC, which cannot parse Tailwind v4 output (`@import "tailwindcss"`
# in the source, cascade layers, media query range syntax). Routing the CSS
# through such a pipeline crashed every asset lookup in the host — including
# unrelated mailer and PDF specs.
RSpec.describe "DataDrip stylesheet delivery", type: :request do
  describe "GET /data_drip/tailwind.css" do
    it "serves the compiled CSS directly, as text/css, without any pipeline" do
      get "/data_drip/tailwind.css"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/css")
      expect(response.body).to include("tailwindcss")
      expect(response.body).to eq(DataDrip.compiled_css)
    end

    it "requires no authentication (carries no tenant data)" do
      # spec_helper wipes all users before each example, so User.first! (the
      # test app's current_user) would raise if this route hit the host's
      # authenticated base controller.
      expect { get "/data_drip/tailwind.css" }.not_to raise_error
      expect(response).to have_http_status(:ok)
    end

    it "sets a far-future, publicly cacheable ETag keyed on the CSS digest" do
      get "/data_drip/tailwind.css"

      expect(response.headers["ETag"]).to be_present
      expect(response.headers["Cache-Control"]).to include("max-age=", "public")

      get "/data_drip/tailwind.css",
          headers: { "HTTP_IF_NONE_MATCH" => response.headers["ETag"] }

      expect(response).to have_http_status(:not_modified)
    end
  end

  describe "the admin layout" do
    let!(:user) { User.create!(name: "Suzie") }

    it "links the stylesheet route with a digest cache-buster, not a pipeline asset" do
      get "/data_drip"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        %(href="/data_drip/tailwind.css?v=#{DataDrip.compiled_css_digest}")
      )
      # No fingerprinted Sprockets/Propshaft asset reference leaks through.
      expect(response.body).not_to match(%r{data_drip/tailwind-[0-9a-f]{7,}\.css})
    end
  end

  describe "engine asset registration" do
    it "registers no engine stylesheet for host precompilation" do
      # The original breakage: the engine pushed `data_drip_manifest.js` onto
      # config.assets.precompile, and its `link_directory` swept every .css in
      # the stylesheet dir into the host's precompile set. On a SassC host the
      # first asset lookup then compiled the Tailwind source and crashed.
      precompile = Rails.application.config.assets.precompile.map(&:to_s)

      expect(precompile).not_to include("data_drip_manifest.js")
      expect(precompile).not_to include(a_string_matching(/data_drip.*\.css/))
    end

    it "no longer ships a Sprockets manifest that sweeps the stylesheets" do
      expect(
        DataDrip::Engine.root.join("app/assets/config/data_drip_manifest.js")
      ).not_to exist
    end

    it "declares the engine JS (but not the CSS) for host precompilation" do
      # A strict Sprockets host (check_precompiled_asset) resolves every pinned
      # importmap module through asset_path when javascript_importmap_tags builds
      # the import map, so the engine JS must be declared for precompilation or
      # the layout raises "asset was not declared to be precompiled". Register
      # plain logical-path strings — never a Regexp, which sprockets-rails'
      # Sprockets::Manifest#find lookup rejects with `start_with?`. The CSS stays
      # out (served by DataDrip::AssetsController), per the tests above.
      precompile = Rails.application.config.assets.precompile.map(&:to_s)

      expect(precompile).to include("data_drip/application.js")
      expect(precompile).to include("data_drip/controllers/autosubmit_controller.js")
      expect(precompile).not_to include(a_string_matching(/data_drip.*\.css/))
    end
  end
end
