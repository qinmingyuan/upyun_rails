require 'upyun'

module ActiveStorage
  # Wraps the upyun Storage Service as an Active Storage service.
  # See ActiveStorage::Service for the generic API documentation that applies to all services.
  #
  #  you can set-up upyun storage service through the generated <tt>config/storage.yml</tt> file.
  #  For example:
  #
  #   upyun:
  #     service: Upyun
  #     bucket: <%= ENV['UPYUN_BUCKET'] %>
  #     operator: <%= ENV['UPYUN_OPERATOR'] %>
  #     password: <%= ENV['UPYUN_PASSWORD'] %>
  #     host: <%= ENV['UPYUN_HOST'] %>
  #     folder: <%= ENV['UPYUN_FOLDER'] %>
  #
  # Then, in your application's configuration, you can specify the service to
  # use like this:
  #
  #   config.active_storage.service = :upyun
  #
  #
  class Service::UpyunService < Service
    ENDPOINT = 'https://v0.api.upyun.com'
    IDENTIFIER = '!'

    attr_reader :upyun, :bucket, :operator, :password, :host, :folder, :upload_options

    def initialize(bucket:, operator:, password:, host:, folder:, **options)
      @client = Upyun::Rest.new(operator, password, **options.slice(:debug))
      @bucket = bucket
      @multipart_upload_threshold = options.delete(:multipart_threshold) || 20.megabytes
      @host = host
      @folder = folder
      @operator = operator
      @password = password
      @upload_options = options
    end

    def upload(key, io, checksum: nil, **options)
      instrument :upload, key: key, checksum: checksum do
        if io.size < @multipart_upload_threshold
          @client.put(path_for(key), io, **options)
        else
          @client.put_chunk(path_for(key), io, per: @multipart_upload_threshold, **options)
        end
      end
    end

    def delete(key)
      instrument :delete, key: key do
        @client.delete(path_for(key))
      end
    end

    def download(key)
      instrument :download, key: key do
        io = @client.get(path_for(key))
        if block_given?
          yield io
        else
          io
        end
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        range_end = range.exclude_end? ? range.end - 1 : range.end
        @client.get(path_for(key), nil, headers: { range: "bytes=#{range.begin}-#{range_end}" })
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        answer = upyun.getinfo(path_for(key))
        result = answer[:error].nil?
        payload[:exist] = result
        result
      end
    end

    def url(key, expires_in:, filename:, content_type:, disposition:, params: {})
      instrument :url, key: key do |payload|
        url = url_for(key, params: params)
        payload[:url] = url
        url
      end
    end

    def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:, **options)
      instrument :url, key: key do |payload|
        url = [ENDPOINT, @bucket , @folder, key].join('/')
        payload[:url] = url
        url
      end
    end

    def headers_for_direct_upload(key, content_type:, checksum:, content_length:, **)
      pwd = Digest::MD5.hexdigest(@password)
      method = 'PUT'
      uri = ["/#{@bucket}", @folder, key].join('/')
      date = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')

      str = [method, uri, date].join("&")
      signature = OpenSSL::HMAC.base64digest('sha1', pwd, str)
      auth = "UPYUN #{@operator}:#{signature}"
      {
        'Content-Type' => content_type,
        'Authorization' => auth,
        'X-Date' => date
      }
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        items = @client.getlist "/#{@folder}/#{prefix}"
        if items.is_a?(Array)
          items.each do |file|
            @client.delete("/#{@folder}/#{prefix}#{file[:name]}")
          end
        end
        @client.delete("/#{@folder}/#{prefix}")
      end
    end

    private
    def url_for(key, params: {})
      url = [@host, @folder, key].join('/')
      return url if params.blank?
      process = params.delete(:process)
      identifier = @upload_options[:identifier] || IDENTIFIER
      url = [url, process].join(identifier) if process
      url
    end

    def path_for(key)
      "/#{@bucket}/#{@folder}/#{key}"
    end

  end
end
