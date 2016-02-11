module Middleman
  module Imageoptim
    require 'image_optim'
    require 'fileutils'
    require 'pathname'

    # Optimizer class that accepts an options object and processes files and
    # passes them off to image_optim to be processed
    class Optimizer
      attr_reader :app, :builder, :options, :byte_savings

      def self.optimize!(app, builder, options)
        new(app, builder, options).process_images
      end

      def initialize(app, builder, options)
        @app = app
        @builder = builder
        @options = options
        @byte_savings = 0
      end

      def process_images
        images = updated_images
        modes = preoptimize_modes(images)
        optimizer.optimize_images(images) do |source, destination|
          process_image(source, destination, modes.fetch(source.to_s))
        end
        update_manifest
        say_status "Total savings: #{Utils.format_size(byte_savings)}"
      end

      private

      def update_manifest
        return unless options.manifest
        manifest.build_and_write(optimizable_images)
        manifest_rel_pth = Pathname.new(manifest.path).relative_path_from(
          Pathname.new(app.root)).to_s
        say_status "#{manifest_rel_pth} updated"
      end

      def process_image(source, destination = nil, mode = nil)
        if destination
          update_bytes_saved(source.size - destination.size)
          say_status '%{source} (%{percent_change} / %{size_change} %{size_change_type})' % Utils.file_size_stats(source, destination)
          FileUtils.move(destination, source)
        else
          say_status "[skipped] #{source} not updated"
        end
      ensure
        ensure_file_mode(mode, source) unless mode.nil?
      end

      def updated_images
        optimizable_images.select { |path| file_updated?(path) }
      end

      def optimizable_images
        build_files.select do |path|
          options.image_extensions.include?(File.extname(path)) && optimizer.optimizable?(path)
        end
      end

      def file_updated?(file_path)
        return true unless options.manifest
        File.mtime(file_path) != manifest.resource(file_path)
      end

      def preoptimize_modes(images)
        images.inject({}) do |modes, image|
          modes[image.to_s] = get_file_mode(image)
          modes
        end
      end

      def build_files
        ::Middleman::Util.all_files_under(app.config.build_dir)
      end

      def say_status(status, target = '')
        builder.trigger(:imageoptim, target, status) if builder
      end

      def optimizer
        @optimizer ||= ImageOptim.new(options.imageoptim_options)
      end

      def manifest
        @manifest ||= Manifest.new(app)
      end

      def update_bytes_saved(bytes)
        @byte_savings += bytes
      end

      def get_file_mode(file)
        sprintf('%o', File.stat(file).mode)[-4, 4].gsub(/^0*/, '')
      end

      def ensure_file_mode(mode, file)
        return if mode == get_file_mode(file)
        FileUtils.chmod(mode.to_i(8), file)
        say_status "fixed file mode on #{file} file to match source"
      end
    end
  end
end
