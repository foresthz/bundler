require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe "Bundler::CLI" do
  describe "it working" do
    before(:each) do
      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        gem "rake"
        gem "extlib"
        gem "very-simple"
        gem "rack", :only => :web
      Gemfile

      Dir.chdir(bundled_app) do
        @output = gem_command :bundle
      end
    end

    it "caches and installs rake" do
      gems = %w(rake-0.8.7 extlib-0.9.12 rack-0.9.1 very-simple-1.0)
      bundled_app("vendor", "gems").should have_cached_gems(*gems)
      bundled_app("vendor", "gems").should have_installed_gems(*gems)
    end

    it "creates a default environment file with the appropriate load paths" do
      bundled_app('vendor', 'gems', 'environment.rb').should have_load_paths(bundled_app("vendor", "gems"),
        "extlib-0.9.12" => %w(lib),
        "rake-0.8.7" => %w(bin lib),
        "very-simple-1.0" => %w(bin lib),
        "rack-0.9.1" => %w(bin lib)
      )
    end

    it "creates an executable for rake in ./bin" do
      out = run_in_context "puts $:"
      out.should include(bundled_app("vendor", "gems", "gems", "rake-0.8.7", "lib").to_s)
      out.should include(bundled_app("vendor", "gems", "gems", "rake-0.8.7", "bin").to_s)
      out.should include(bundled_app("vendor", "gems", "gems", "extlib-0.9.12", "lib").to_s)
      out.should include(bundled_app("vendor", "gems", "gems", "very-simple-1.0", "lib").to_s)
      out.should include(bundled_app("vendor", "gems", "gems", "rack-0.9.1").to_s)
    end

    it "creates valid executables" do
      out = `#{bundled_app("bin", "rake")} -e 'require "extlib" ; puts Extlib'`.strip
      out.should == "Extlib"
    end

    it "runs exec correctly" do
      Dir.chdir(bundled_app) do
        out = gem_command :exec, %[ruby -e 'require "extlib" ; puts Extlib']
        out.should == "Extlib"
      end
    end

    it "maintains the correct environment when shelling out" do
      out = run_in_context "exec %{#{Gem.ruby} -e 'require %{very-simple} ; puts VerySimpleForTests'}"
      out.should == "VerySimpleForTests"
    end

    it "logs the correct information messages" do
      [ "Updating source: file:#{gem_repo1}",
        "Calculating dependencies...",
        "Downloading rake-0.8.7.gem",
        "Downloading extlib-0.9.12.gem",
        "Downloading rack-0.9.1.gem",
        "Downloading very-simple-1.0.gem",
        "Installing rake (0.8.7)",
        "Installing extlib (0.9.12)",
        "Installing rack (0.9.1)",
        "Installing very-simple (1.0)",
        "Done." ].each do |message|
          @output.should =~ /^#{Regexp.escape(message)}$/
        end
    end

    it "already has gems in the loaded_specs" do
      out = run_in_context "puts Gem.loaded_specs.key?('extlib')"
      out.should == "true"
    end

    it "does already has rubygems required" do
      out = run_in_context "puts Gem.respond_to?(:sources)"
      out.should == "true"
    end

    # TODO: Remove this when rubygems is fixed
    it "adds the gem to Gem.source_index" do
      out = run_in_context "puts Gem.source_index.find_name('very-simple').first.version"
      out.should == "1.0"
    end
  end

  describe "error cases" do
    before(:each) do
      bundled_app.mkdir_p
      Dir.chdir(bundled_app)
    end

    it "displays a friendly error message when there is no Gemfile" do
      out = gem_command :bundle
      out.should == "Could not find a Gemfile to use"
    end

    it "fails when a root level gem does not exist" do
      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        gem "monk"
      Gemfile

      out = gem_command :bundle
      out.should include("Could not find gem 'monk (>= 0, runtime)' in any of the sources")
    end

    it "outputs a warning when a child gem dependency is missing dependencies" do
      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        gem "treetop"
      Gemfile

      out = gem_command :bundle
      out.should include("Could not find gem 'polyglot (>= 0.2.5, runtime)' (required by 'treetop (>= 0, runtime)') in any of the sources")
    end
  end

  describe "it working while specifying the manifest file name" do
    it "works when the manifest is in the root directory" do
      build_manifest_file bundled_app('manifest.rb'), <<-Gemfile
        bundle_path "gems"
        clear_sources
        source "file://#{gem_repo1}"
        gem "rake"
      Gemfile

      Dir.chdir(bundled_app)
      gem_command :bundle, "-m #{bundled_app('manifest.rb')}"
      bundled_app("gems").should have_cached_gems("rake-0.8.7")
    end

    it "works when the manifest is in a different directory" do
      build_manifest_file bundled_app('config', 'manifest.rb'), <<-Gemfile
        bundle_path "../gems"
        clear_sources
        source "file://#{gem_repo1}"
        gem "rake"
      Gemfile

      Dir.chdir(bundled_app)
      gem_command :bundle, "-m #{bundled_app('config', 'manifest.rb')}"
      bundled_app("gems").should have_cached_gems("rake-0.8.7")
    end
  end

  describe "it working without rubygems" do
    before(:each) do
      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        gem "rake"
        gem "extlib"
        gem "rack", :only => :web

        disable_rubygems
      Gemfile

      Dir.chdir(bundled_app) do
        @output = gem_command :bundle
      end
    end

    it "does not load rubygems when required" do
      out = run_in_context 'require "rubygems" ; puts Gem.respond_to?(:sources)'
      out.should == "false"
    end

    it "does not blow up if #gem is used" do
      out = run_in_context 'gem("merb-core") ; puts "Win!"'
      out.should == "Win!"
    end

    it "does not blow up if Gem errors are referred to" do
      out = run_in_context 'Gem::LoadError ; Gem::Exception ; puts "Win!"'
      out.should == "Win!"
    end

    it "stubs out Gem.ruby" do
      out = run_in_context "puts Gem.ruby"
      out.should == Gem.ruby
    end
  end

  describe "forcing an update" do
    it "forces checking for remote updates if --update is used" do
      m = build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        source "file://#{gem_repo2}"
        gem "rack", "0.9.1"
      Gemfile
      m.install

      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        source "file://#{gem_repo2}"
        gem "rack"
      Gemfile

      Dir.chdir(bundled_app) do
        gem_command :bundle, "--update"
      end
      bundled_app("vendor", "gems").should include_cached_gems("rack-1.0.0")
      bundled_app("vendor", "gems").should have_installed_gems("rack-1.0.0")
    end
  end

  describe "bundling from the local cache" do
    before(:each) do
      install_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo1}"
        gem "rack", "0.9.1"
      Gemfile

      %w(doc environment.rb gems specifications).each do |f|
        FileUtils.rm_rf(tmp_gem_path.join(f))
      end
    end

    it "only uses the localy cached gems when bundling with --cache" do
      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo2}"
        gem "rack"
      Gemfile

      Dir.chdir(bundled_app) do
        gem_command :bundle, "--cached"
        tmp_gem_path.should include_cached_gems("rack-0.9.1")
        tmp_gem_path.should have_installed_gems("rack-0.9.1")
      end
    end

    it "raises an exception when there are missing gems in the cache" do
      Dir["#{tmp_gem_path}/cache/*"].each { |f| FileUtils.rm_rf(f) }

      build_manifest <<-Gemfile
        clear_sources
        source "file://#{gem_repo2}"
        gem "rack"
      Gemfile

      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cached"
        out.should include("Could not find gem 'rack (>= 0, runtime)' in any of the sources")
        tmp_gem_path.should_not include_cached_gems("rack-0.9.1", "rack-1.0.0")
        tmp_gem_path.should_not include_installed_gems("rack-0.9.1", "rack-1.0.0")
      end
    end
  end

  describe "caching gems to the bundle" do
    before(:each) do
      build_manifest <<-Gemfile
        clear_sources
      Gemfile
    end

    it "adds a single gem to the cache" do
      build_manifest <<-Gemfile
        clear_sources
        gem "rack"
      Gemfile

      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cache #{gem_repo1('gems', 'rack-0.9.1.gem')}"
        gem_command :bundle, "--cached"
        out.should include("Caching: rack-0.9.1.gem")
        tmp_gem_path.should include_cached_gems("rack-0.9.1")
        tmp_gem_path.should include_installed_gems("rack-0.9.1")
      end
    end

    it "adds a gem directory to the cache" do
      build_manifest <<-Gemfile
        clear_sources
        gem "rack"
        gem "abstract"
      Gemfile

      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cache #{gem_repo1('gems')}"
        gem_command :bundle, "--cached"

        %w(abstract-1.0.0 actionmailer-2.3.2 activerecord-2.3.2 addressable-2.0.2 builder-2.1.2).each do |gemfile|
          out.should include("Caching: #{gemfile}.gem")
        end
        tmp_gem_path.should include_cached_gems("rack-0.9.1", "abstract-1.0.0")
        tmp_gem_path.should have_installed_gems("rack-0.9.1", "abstract-1.0.0")
      end
    end

    it "adds a gem from the local repository" do
      build_manifest <<-Gemfile
        clear_sources
        gem "rspec"
        disable_system_gems
      Gemfile

      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cache rspec"
        gem_command :bundle, "--cached"
         out = run_in_context "require 'spec' ; puts Spec"
         out.should == "Spec"
      end
    end

    it "outputs an error when trying to cache a gem that doesn't exist." do
      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cache foo/bar.gem"
        out.should == "'foo/bar.gem' does not exist."
      end
    end

    it "outputs an error when trying to cache a directory that doesn't exist." do
      Dir.chdir(bundled_app) do
        out = gem_command :bundle, "--cache foo/bar"
        out.should == "'foo/bar' does not exist."
      end
    end

    it "outputs an error when trying to cache a directory with no gems." do
      Dir.chdir(bundled_app) do
        FileUtils.mkdir_p("foo/bar")
        out = gem_command :bundle, "--cache foo/bar"
        out.should == "'foo/bar' contains no gemfiles"
      end
    end
  end
end
