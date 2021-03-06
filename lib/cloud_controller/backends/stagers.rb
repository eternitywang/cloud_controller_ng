require "cloud_controller/dea/stager"
require "cloud_controller/diego/stager"
require "cloud_controller/diego/traditional/protocol"
require "cloud_controller/diego/traditional/staging_completion_handler"
require "cloud_controller/diego/docker/protocol"
require "cloud_controller/diego/docker/staging_completion_handler"
require "cloud_controller/diego/common/protocol"

module VCAP::CloudController
  class Stagers
    def initialize(config, message_bus, dea_pool, stager_pool, runners)
      @config = config
      @message_bus = message_bus
      @dea_pool = dea_pool
      @stager_pool = stager_pool
      @runners = runners
    end

    def validate_app(app)

      if app.docker_image.present? && docker_disabled?
        raise Errors::ApiError.new_from_details("DockerDisabled")
      end

      if app.package_hash.blank?
        raise Errors::ApiError.new_from_details("AppPackageInvalid", "The app package hash is empty")
      end

      if app.buildpack.custom? && !app.custom_buildpacks_enabled?
        raise Errors::ApiError.new_from_details("CustomBuildpacksDisabled")
      end

      if Buildpack.count == 0 && app.buildpack.custom? == false
        raise Errors::ApiError.new_from_details("NoBuildpacksFound")
      end
    end

    def stager_for_app(app)
      return dea_stager(app) if diego_staging_disabled?

      app.stage_with_diego? ? diego_stager(app) : dea_stager(app)
    end

    private

    def diego_staging_disabled?
      @diego_disabled ||= @config[:diego][:staging] == 'disabled'
    end

    def docker_disabled?
      !@config[:diego_docker]
    end

    def dea_stager(app)
      Dea::Stager.new(app, @config, @message_bus, @dea_pool, @stager_pool, @runners)
    end

    def diego_stager(app)
      app.docker_image.present? ? diego_docker_stager(app) : diego_traditional_stager(app)
    end

    def diego_docker_stager(app)
      protocol = Diego::Docker::Protocol.new(Diego::Common::Protocol.new)
      messenger = Diego::Messenger.new(@message_bus, protocol)
      completion_handler = Diego::Docker::StagingCompletionHandler.new(@runners)
      Diego::Stager.new(app, messenger, completion_handler, staging_timeout)
    end

    def diego_traditional_stager(app)
      dependency_locator = CloudController::DependencyLocator.instance
      protocol = Diego::Traditional::Protocol.new(dependency_locator.blobstore_url_generator, Diego::Common::Protocol.new)
      messenger = Diego::Messenger.new(@message_bus, protocol)
      completion_handler = Diego::Traditional::StagingCompletionHandler.new(@runners)
      Diego::Stager.new(app, messenger, completion_handler, staging_timeout)
    end

    def staging_timeout
      @config[:staging][:timeout_in_seconds]
    end
  end
end
